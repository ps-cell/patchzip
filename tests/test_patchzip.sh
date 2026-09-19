#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
BIN="$ROOT/patchzip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
run_test() {
    local name=$1
    shift
    if "$@"; then
        printf 'PASS %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$name" >&2
        fail=$((fail + 1))
    fi
}

make_zip() {
    local src=$1 zip=$2
    (cd "$src" && zip -qr "$zip" .)
}

basic_test() {
    local d="$TMP/basic" dl="$TMP/downloads"
    mkdir -p "$d" "$dl"
    printf 'old\n' > "$d/file.txt"
    printf 'keep\n' > "$d/keep.txt"
    printf 'oldzip\n' > "$d/project-v0.1.zip"
    mkdir -p "$TMP/new"
    printf 'new\n' > "$TMP/new/file.txt"
    make_zip "$TMP/new" "$dl/project-v0.2.zip"
    HOME="$TMP" bash -c "cd '$d' && '$BIN' '$dl/project-v0.2.zip' --yes --no-setup --no-test"
    [[ $(cat "$d/file.txt") == new ]]
    [[ $(cat "$d/keep.txt") == keep ]]
    [[ -f "$d/project-v0.2.zip" ]]
    [[ ! -f "$d/project-v0.1.zip" ]]
    cmp -s "$d/.patchdir/project-v0.1.zip" <(printf 'oldzip\n')
}


undelimited_version_old_archive_test() {
    local d="$TMP/undelimited" dl="$TMP/downloads20" new="$TMP/new20"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf new > "$new/a"
    printf oldzip > "$d/monte0.0.3.zip"
    make_zip "$new" "$dl/monte0.0.4.zip"
    (cd "$d" && "$BIN" "$dl/monte0.0.4.zip" --yes --no-setup --no-test >/dev/null)
    [[ -f "$d/monte0.0.4.zip" ]]
    [[ ! -f "$d/monte0.0.3.zip" ]]
}

no_delete_unrelated() {
    local d="$TMP/unrelated" dl="$TMP/downloads2"
    mkdir -p "$d" "$dl"
    printf x > "$d/unrelated.zip"
    mkdir -p "$TMP/new2"
    printf y > "$TMP/new2/a"
    make_zip "$TMP/new2" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test >/dev/null)
    [[ -f "$d/unrelated.zip" ]]
}

unsafe_test() {
    local d="$TMP/unsafe" dl="$TMP/downloads3"
    mkdir -p "$d" "$dl" "$TMP/evil"
    printf x > "$TMP/evil/normal"
    (cd "$TMP/evil" && zip -q "$dl/project-v1.zip" normal)
    # Append a traversal member with zip's -j path behavior avoided by constructing it via Python.
    python3 - "$dl/project-v1.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'a') as z:
    z.writestr('../../escape.txt', 'bad')
PY
    ! (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test >/dev/null 2>&1)
    [[ ! -f "$TMP/escape.txt" ]]
}

dry_run_test() {
    local d="$TMP/dry" dl="$TMP/downloads4"
    mkdir -p "$d" "$dl" "$TMP/new4"
    printf old > "$d/a"
    printf new > "$TMP/new4/a"
    make_zip "$TMP/new4" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" --dry-run "$dl/project-v1.zip" --yes --no-setup --no-test >/dev/null)
    [[ $(cat "$d/a") == old ]]
    [[ ! -f "$d/project-v1.zip" ]]
}

hooks_test() {
    local d="$TMP/hooks" dl="$TMP/downloads5"
    mkdir -p "$d" "$dl" "$TMP/new5"
    printf new > "$TMP/new5/a"
    make_zip "$TMP/new5" "$dl/project-v1.zip"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
printf setup-ran > setup.out
SH
    cat > "$d/run_test.sh" <<'SH'
#!/usr/bin/env bash
[[ -f setup.out ]]
printf test-ran > test.out
SH
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ -f "$d/setup.out" && -f "$d/test.out" ]]
}


plural_test_hook_test() {
    local d="$TMP/pluralhook" dl="$TMP/downloads21" new="$TMP/new21"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    printf '%s\n' '#!/usr/bin/env bash' 'printf test-ran > test.out' > "$new/run_tests.sh"
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup >/dev/null)
    [[ -f "$d/test.out" ]]
}

run_test basic basic_test
run_test undelimited_version_old_archive undelimited_version_old_archive_test

version_suffix_test() {
    local d="$TMP/version_suffix" dl="$TMP/downloads21" new="$TMP/new21"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf new > "$new/a"
    printf oldzip > "$d/web-v0.1.1.zip"
    make_zip "$new" "$dl/web-v0.1.2.zip"
    (cd "$d" && "$BIN" "$dl/web-v0.1.2.zip" --yes --no-setup --no-test >/dev/null)
    [[ -f "$d/web-v0.1.2.zip" ]]
    [[ ! -f "$d/web-v0.1.1.zip" ]]
}
run_test plural_test_hook plural_test_hook_test
run_test unrelated_zip_preserved no_delete_unrelated
run_test unsafe_zip_rejected unsafe_test
run_test dry_run dry_run_test
run_test hooks hooks_test



setup_runs_tests_once_test() {
    local d="$TMP/setup-runs-tests-once" dl="$TMP/downloads-setup-tests-once" new="$TMP/new-setup-tests-once"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    cat > "$new/run_tests.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-none}" >> test-runs.log
SH
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
set -e
./run_tests.sh from-setup
printf setup-ran > setup.out
SH
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ $(wc -l < "$d/test-runs.log") -eq 1 ]]
    [[ $(cat "$d/test-runs.log") == from-setup ]]
    [[ -f "$d/setup.out" ]]
}

setup_runs_bare_test_hook_once_test() {
    local d="$TMP/setup-runs-bare-test-hook-once" dl="$TMP/downloads-setup-bare-test-hook-once" new="$TMP/new-setup-bare-test-hook-once"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    cat > "$new/run_tests.sh" <<'SH'
#!/usr/bin/env bash
[[ -e .TESTS_FLAG ]]
printf test-ran >> test.out
SH
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
set -e
run_tests.sh
SH
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ $(cat "$d/test.out") == test-ran ]]
    [[ ! -e "$d/.TESTS_FLAG" ]]
}

setup_runs_failing_tests_once_test() {
    local d="$TMP/setup-runs-failing-tests-once" dl="$TMP/downloads-setup-failing-tests-once" new="$TMP/new-setup-failing-tests-once"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    cat > "$new/run_tests.sh" <<'SH'
#!/usr/bin/env bash
printf test-ran >> test.out
exit 17
SH
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
# Deliberately ignore the test hook's failure; patchzip must still propagate it.
./run_tests.sh || true
printf setup-ran > setup.out
SH
    make_zip "$new" "$dl/project-v1.zip"
    if (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null 2>&1); then
        return 1
    fi
    [[ $(cat "$d/test.out") == test-ran ]]
    [[ -f "$d/setup.out" ]]
}

setup_direct_pytest_does_not_count_as_hook_test() {
    local d="$TMP/setup-runs-direct-pytest" dl="$TMP/downloads-setup-direct-pytest" new="$TMP/new-setup-direct-pytest"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    cat > "$new/run_tests.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -x .venv/bin/python ]]
printf hook-run >> test-runs.log
SH
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
VENV_PYTHON="${VENV_DIR:-.venv}/bin/python"
mkdir -p "$(dirname "$VENV_PYTHON")"
cat > "$VENV_PYTHON" <<'PY'
#!/usr/bin/env bash
if [[ "${1:-}" == "-m" && "${2:-}" == "pytest" ]]; then
    printf pytest-run >> test-runs.log
    exit 0
fi
exit 99
PY
chmod +x "$VENV_PYTHON"
exec "$VENV_PYTHON" -m pytest -m 'not integration' "$@"
SH
    chmod +x "$d/setup.sh"
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ $(cat "$d/test-runs.log") == pytest-runhook-run ]]
}

setup_hook_uses_project_venv_test() {
    local d="$TMP/setup-hook-project-venv" dl="$TMP/downloads-setup-hook-project-venv" new="$TMP/new-setup-hook-project-venv"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    cat > "$new/run_tests.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -x .venv/bin/python ]]
printf hook-ran > test.out
SH
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .venv/bin
printf '#!/usr/bin/env bash\n' > .venv/bin/python
chmod +x .venv/bin/python
run_tests.sh
SH
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ $(cat "$d/test.out") == hook-ran ]]
}

setup_failure_test() {
    local d="$TMP/setupfail" dl="$TMP/downloads6"
    mkdir -p "$d" "$dl" "$TMP/new6"
    printf new > "$TMP/new6/a"
    make_zip "$TMP/new6" "$dl/project-v1.zip"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 7' > "$d/setup.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'touch test-ran' > "$d/run_test.sh"
    ! (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null 2>&1)
    [[ ! -f "$d/test-ran" ]]
}

test_failure_test() {
    local d="$TMP/testfail" dl="$TMP/downloads7"
    mkdir -p "$d" "$dl" "$TMP/new7"
    printf new > "$TMP/new7/a"
    make_zip "$TMP/new7" "$dl/project-v1.zip"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 9' > "$d/run_test.sh"
    ! (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null 2>&1)
    [[ $(cat "$d/a") == new ]]
}

multiple_old_test() {
    local d="$TMP/multiple" dl="$TMP/downloads8"
    mkdir -p "$d" "$dl" "$TMP/new8"
    printf new > "$TMP/new8/a"
    make_zip "$TMP/new8" "$dl/project-v2.zip"
    printf old1 > "$d/project-v1.zip"
    printf old09 > "$d/project-v0.9.zip"
    (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test >/dev/null)
    [[ -f "$d/project-v2.zip" ]]
    [[ -f "$d/project-v1.zip" ]]
    [[ ! -f "$d/project-v0.9.zip" ]]
    [[ $(cat "$d/.patchdir/project-v1.zip") == old1 ]]
}

symlink_test() {
    local d="$TMP/symlink" dl="$TMP/downloads9"
    mkdir -p "$d" "$dl" "$TMP/new9"
    printf payload > "$TMP/new9/target"
    ln -s target "$TMP/new9/link"
    (cd "$TMP/new9" && zip -qyr "$dl/project-v1.zip" .)
    ! (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test >/dev/null 2>&1)
    [[ ! -L "$d/link" ]]
}

run_test setup_hook_uses_project_venv setup_hook_uses_project_venv_test
run_test setup_failure setup_failure_test
run_test setup_direct_pytest_does_not_count_as_hook setup_direct_pytest_does_not_count_as_hook_test
run_test setup_runs_tests_once setup_runs_tests_once_test
run_test setup_runs_bare_test_hook_once setup_runs_bare_test_hook_once_test

setup_runs_exec_test_hook_once_test() {
    local d="$TMP/setup-runs-exec-test-hook-once" dl="$TMP/downloads-setup-exec-test-hook-once" new="$TMP/new-setup-exec-test-hook-once"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    printf '#!/usr/bin/env bash\nprintf exec-ran >> test-runs.log\n' > "$new/run_tests.sh"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
set -e
exec ./run_tests.sh
SH
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ $(cat "$d/test-runs.log") == exec-ran ]]
    [[ ! -e "$d/.TESTS_FLAG" ]]
}

run_test setup_runs_exec_test_hook_once setup_runs_exec_test_hook_once_test

setup_runs_legacy_test_hook_once_test() {
    local d="$TMP/setup-runs-legacy-test-hook-once" dl="$TMP/downloads-setup-legacy-test-hook-once" new="$TMP/new-setup-legacy-test-hook-once"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    printf '#!/usr/bin/env bash\nprintf legacy-ran >> test-runs.log\n' > "$new/run_test.sh"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
set -e
./run_test.sh
SH
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ $(cat "$d/test-runs.log") == legacy-ran ]]
    [[ ! -e "$d/.TESTS_FLAG" ]]
}

run_test setup_runs_legacy_test_hook_once setup_runs_legacy_test_hook_once_test

setup_hook_detection_ignores_bash_env_test() {
    local d="$TMP/setup-hook-detection-bash-env" dl="$TMP/downloads-setup-hook-detection-bash-env" new="$TMP/new-setup-hook-detection-bash-env" env="$TMP/bash-env-setup-hook-detection"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    printf '#!/usr/bin/env bash\nprintf bash-env-ran >> test-runs.log\n' > "$new/run_tests.sh"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
set -e
run_tests.sh
SH
    printf "PS4='CUSTOM-PS4: '\n" > "$env"
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && BASH_ENV="$env" "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ $(cat "$d/test-runs.log") == bash-env-ran ]]
}

run_test setup_hook_detection_ignores_bash_env setup_hook_detection_ignores_bash_env_test

setup_failure_after_test_hook_test() {
    local d="$TMP/setup-failure-after-test-hook" dl="$TMP/downloads-setup-failure-after-test-hook" new="$TMP/new-setup-failure-after-test-hook"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    printf '#!/usr/bin/env bash\nprintf hook-ran > hook.out\n' > "$new/run_tests.sh"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
./run_tests.sh
exit 17
SH
    make_zip "$new" "$dl/project-v1.zip"
    ! (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null 2>&1)
    [[ -f "$d/hook.out" ]]
}

run_test setup_failure_after_test_hook setup_failure_after_test_hook_test

setup_hook_failure_cleans_tests_flag_test() {
    local d="$TMP/setup-hook-failure-cleans-tests-flag" dl="$TMP/downloads-setup-hook-failure-cleans-tests-flag" new="$TMP/new-setup-hook-failure-cleans-tests-flag"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    printf '#!/usr/bin/env bash\n[[ -e .TESTS_FLAG ]]\nexit 23\n' > "$new/run_tests.sh"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
./run_tests.sh
SH
    make_zip "$new" "$dl/project-v1.zip"
    ! (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null 2>&1)
    [[ ! -e "$d/.TESTS_FLAG" ]]
}

run_test setup_hook_failure_cleans_tests_flag setup_hook_failure_cleans_tests_flag_test

run_test setup_runs_failing_tests_once setup_runs_failing_tests_once_test
run_test test_failure test_failure_test
run_test multiple_old_archives multiple_old_test
run_test symlink_rejected symlink_test

auto_selection_test() {
    local d="$TMP/project" dl="$TMP/Downloads"
    mkdir -p "$d" "$dl" "$TMP/new10"
    printf new > "$TMP/new10/a"
    make_zip "$TMP/new10" "$dl/project-v1.zip"
    : > "$dl/unrelated.zip"
    HOME="$TMP" bash -c "cd '$d' && '$BIN' --yes --no-setup --no-test" >/dev/null
    [[ -f "$d/project-v1.zip" && $(cat "$d/a") == new ]]
}

run_test automatic_project_selection auto_selection_test

namespace_project_selection_test() {
    local d="$TMP/agent-runtime" home="$TMP/home-namespace" dl="$TMP/home-namespace/Downloads" new="$TMP/new-namespace"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf new > "$new/a"
    make_zip "$new" "$dl/jeb-agent-runtime-v0.5.11.zip"
    make_zip "$new" "$dl/rag-api-v0.3.1.zip"
    make_zip "$new" "$dl/workspace-service-v0.8.10.zip"
    HOME="$home" bash -c "cd '$d' && '$BIN' --yes --no-setup --no-test" >/dev/null
    [[ -f "$d/jeb-agent-runtime-v0.5.11.zip" && $(cat "$d/a") == new ]]
    [[ ! -f "$d/rag-api-v0.3.1.zip" && ! -f "$d/workspace-service-v0.8.10.zip" ]]
}

run_test namespace_project_selection namespace_project_selection_test

case_insensitive_download_selection_test() {
    local d="$TMP/MCP-manager" dl="$TMP/home-case/Downloads" new="$TMP/new-case"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf new > "$new/a"
    make_zip "$new" "$dl/mcp-manager-v0.4.2(2).zip"
    make_zip "$new" "$dl/jeb-agent-runtime-v0.5.14(2).zip"
    HOME="$TMP/home-case" bash -c "cd '$d' && '$BIN' --yes --no-setup --no-test" >/dev/null
    [[ $(cat "$d/a") == new ]]
    [[ -f "$d/mcp-manager-v0.4.2(2).zip" ]]
    [[ ! -f "$d/jeb-agent-runtime-v0.5.14(2).zip" ]]
}

run_test case_insensitive_download_selection case_insensitive_download_selection_test


confirmation_required_test() {
    local d="$TMP/confirm" dl="$TMP/downloads11"
    mkdir -p "$d" "$dl" "$TMP/new11"
    printf old > "$d/a"
    printf new > "$TMP/new11/a"
    make_zip "$TMP/new11" "$dl/project-v1.zip"
    if (cd "$d" && "$BIN" "$dl/project-v1.zip" --no-setup --no-test >/dev/null 2>&1); then
        return 1
    fi
    [[ $(cat "$d/a") == old ]]
    [[ ! -f "$d/project-v1.zip" ]]
}

noninteractive_yes_test() {
    local d="$TMP/yes" dl="$TMP/downloads12"
    mkdir -p "$d" "$dl" "$TMP/new12"
    printf old > "$d/a"
    printf new > "$TMP/new12/a"
    make_zip "$TMP/new12" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test >/dev/null)
    [[ $(cat "$d/a") == new ]]
}

run_test confirmation_required confirmation_required_test
run_test noninteractive_yes noninteractive_yes_test


interactive_confirmation_test() {
    local d="$TMP/interactive" dl="$TMP/downloads13"
    mkdir -p "$d" "$dl" "$TMP/new13"
    printf old > "$d/a"
    printf new > "$TMP/new13/a"
    make_zip "$TMP/new13" "$dl/project-v1.zip"
    PATCHZIP_BIN="$BIN" TEST_PROJECT="$d" TEST_ARCHIVE="$dl/project-v1.zip" python3 - <<'PY2'
import os, pty, select

pid, fd = pty.fork()
if pid == 0:
    os.chdir(os.environ["TEST_PROJECT"])
    os.execv(os.environ["PATCHZIP_BIN"], [os.environ["PATCHZIP_BIN"], os.environ["TEST_ARCHIVE"], "--no-setup", "--no-test"])

buf = b""
while True:
    ready, _, _ = select.select([fd], [], [], 5)
    if not ready:
        os.kill(pid, 9)
        raise SystemExit("timed out waiting for confirmation prompt")
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    buf += chunk
    if b"Continue? [Y/n]" in buf:
        os.write(fd, b"n\n")
        break

_, status = os.waitpid(pid, 0)
if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
    raise SystemExit("patchzip cancellation did not exit cleanly")
if open(os.path.join(os.environ["TEST_PROJECT"], "a")).read() != "old":
    raise SystemExit("project changed after cancellation")
if os.path.exists(os.path.join(os.environ["TEST_PROJECT"], "project-v1.zip")):
    raise SystemExit("archive was installed after cancellation")
PY2
}

run_test interactive_confirmation interactive_confirmation_test

report_test() {
    local d="$TMP/report" dl="$TMP/downloads14"
    mkdir -p "$d" "$dl" "$TMP/new14"
    printf old > "$d/replaced.txt"
    printf keep > "$d/kept.txt"
    printf new > "$TMP/new14/replaced.txt"
    printf added > "$TMP/new14/added.txt"
    make_zip "$TMP/new14" "$dl/project-v1.zip"
    local output
    output=$(cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test)
    [[ $output == *'Patch report'* ]]
    [[ $output == *'Files in ZIP:  2'* ]]
    [[ $output == *'Replaces:      1 file(s)'* ]]
    [[ $output == *'Adds:          1 file(s)'* ]]
    [[ $output == *'Result:        success'* ]]
}

run_test patch_report report_test


type_conflict_test() {
    local d="$TMP/typeconflict" dl="$TMP/downloads15"
    mkdir -p "$d/conflict" "$dl" "$TMP/new15"
    printf old > "$d/conflict/old.txt"
    printf new > "$TMP/new15/conflict"
    make_zip "$TMP/new15" "$dl/project-v1.zip"
    ! (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test >/dev/null 2>&1)
    [[ -f "$d/conflict/old.txt" ]]
    [[ ! -f "$d/project-v1.zip" ]]
}

run_test type_conflict type_conflict_test



ancestor_type_conflict_test() {
    local d="$TMP/ancestorconflict" dl="$TMP/downloads-ancestor-conflict" new="$TMP/new-ancestor-conflict"
    mkdir -p "$d" "$dl" "$new/.venv/bin"
    printf old > "$d/.venv"
    printf new > "$new/.venv/bin/python"
    make_zip "$new" "$dl/project-v1.zip"
    local output
    if output=$(cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test 2>&1); then
        return 1
    fi
    [[ $output == *"blocked by project file '.venv'"* ]]
    [[ $(cat "$d/.venv") == old ]]
    [[ ! -f "$d/project-v1.zip" ]]
}

run_test ancestor_type_conflict ancestor_type_conflict_test

existing_symlink_rejected_test() {
    local d="$TMP/existing-symlink" dl="$TMP/downloads-existing-symlink" new="$TMP/new-existing-symlink"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/target"
    ln -s target "$d/a"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v1.zip"
    ! (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test >/dev/null 2>&1)
    [[ -L "$d/a" ]]
    [[ $(readlink "$d/a") == target ]]
    [[ ! -f "$d/project-v1.zip" ]]
}

run_test existing_symlink_rejected existing_symlink_rejected_test

no_staging_directory_test() {
    local d="$TMP/nostaging" dl="$TMP/downloads-nostaging" new="$TMP/new-nostaging"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && TMPDIR="$d" "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test >/dev/null)
    ! find "$d" -maxdepth 1 -type d -name 'patchzip.*' -print -quit | grep -q .
    [[ $(cat "$d/a") == new ]]
}

run_test no_staging_directory no_staging_directory_test

canonical_hyphenated_version_name_test() {
    local d="$TMP/canonical-name" dl="$TMP/downloads-canonical-name" new="$TMP/new-canonical-name"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v-2.0.0.zip"
    printf oldzip > "$d/project-v-1.9.0.zip"
    (cd "$d" && "$BIN" "$dl/project-v-2.0.0.zip" --yes --no-setup --no-test >/dev/null)
    [[ $(cat "$d/a") == new ]]
    [[ -f "$d/project-v-2.0.0.zip" ]]
    [[ ! -f "$d/project-v-1.9.0.zip" ]]
    [[ -f "$d/.patchdir/project-v-1.9.0.zip" ]]
}

run_test canonical_hyphenated_version_name canonical_hyphenated_version_name_test

self_patch_test() {
    local d="$TMP/selfpatch" dl="$TMP/downloads16" new="$TMP/new16" bin="$TMP/bin16"
    mkdir -p "$d" "$dl" "$new" "$bin"
    cp "$BIN" "$d/patchzip"
    cp "$BIN" "$new/patchzip"
    sed -i "s/VERSION='0.4.24'/VERSION='0.4.1'/" "$new/patchzip"
    printf 'old\n' > "$d/payload.txt"
    printf 'new\n' > "$new/payload.txt"
    ln -s "$d/patchzip" "$bin/patchzip"
    (cd "$new" && zip -qr "$dl/selfpatch-v1.zip" .)
    (cd "$d" && "$bin/patchzip" "$dl/selfpatch-v1.zip" --yes --no-setup --no-test >/dev/null)
    [[ $(cat "$d/payload.txt") == new ]]
    [[ $(grep -m1 "^VERSION=" "$d/patchzip") == "VERSION='0.4.1'" ]]
    [[ $($bin/patchzip --version) == 0.4.1 ]]
}

run_test self_patch self_patch_test



default_yes_test() {
    local d="$TMP/defaultyes" dl="$TMP/downloads17" new="$TMP/new17"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v1.zip"
    PATCHZIP_BIN="$BIN" TEST_PROJECT="$d" TEST_ARCHIVE="$dl/project-v1.zip" python3 - <<'PY2'
import os, pty, select
pid, fd = pty.fork()
if pid == 0:
    os.chdir(os.environ["TEST_PROJECT"])
    os.execv(os.environ["PATCHZIP_BIN"], [os.environ["PATCHZIP_BIN"], os.environ["TEST_ARCHIVE"], "--no-setup", "--no-test"])
buf = b""
while True:
    ready, _, _ = select.select([fd], [], [], 5)
    if not ready:
        os.kill(pid, 9)
        raise SystemExit("timed out waiting for confirmation prompt")
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    buf += chunk
    if b"Continue? [Y/n]" in buf:
        os.write(fd, b"\n")
        break
_, status = os.waitpid(pid, 0)
if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
    raise SystemExit("default-yes confirmation did not accept Enter")
if open(os.path.join(os.environ["TEST_PROJECT"], "a")).read() != "new":
    raise SystemExit("Enter did not accept the confirmation")
PY2
}

run_test default_yes default_yes_test

fallback_backup_name_test() {
    local d="$TMP/fallback-backup" dl="$TMP/downloads-fallback-backup" new="$TMP/new-fallback-backup"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf oldzip > "$d/project-1.zip"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-2.zip"
    (cd "$d" && "$BIN" "$dl/project-2.zip" --yes --no-setup --no-test >/dev/null)
    [[ -f "$d/.patchdir/previous-version.zip" ]]
    [[ $(cat "$d/.patchdir/previous-version.zip") == oldzip ]]
}

run_test fallback_backup_name fallback_backup_name_test

duplicate_download_suffix_test() {
    local d="$TMP/dupesuffix" dl="$TMP/downloads20" new="$TMP/new20"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    printf oldzip > "$d/project-v1.zip"
    local output
    output=$(cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test)
    [[ $(cat "$d/a") == new ]]
    [[ -f "$d/project-v2.zip" ]]
    [[ ! -f "$d/project-v1.zip" ]]
    [[ $output == *'Retired ZIP:   project-v1.zip'* ]]

    rm -f "$d/project-v2.zip" "$d/project-v1.zip"
    make_zip "$new" "$dl/project-v2(1).zip"
    printf oldzip > "$d/project-v1.zip"
    output=$(cd "$d" && "$BIN" "$dl/project-v2(1).zip" --yes --no-setup --no-test)
    [[ $(cat "$d/a") == new ]]
    [[ -f "$d/project-v2(1).zip" ]]
    [[ ! -f "$d/project-v1.zip" ]]
    [[ $output == *'Retired ZIP:   project-v1.zip'* ]]
}

run_test duplicate_download_suffix duplicate_download_suffix_test

duplicate_existing_archive_suffix_test() {
    local d="$TMP/dupe-existing" dl="$TMP/downloads-dupe-existing" new="$TMP/new-dupe-existing"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf oldzip > "$d/project-v1(1).zip"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    local output
    output=$(cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test)
    [[ $(cat "$d/a") == new ]]
    [[ -f "$d/project-v2.zip" ]]
    [[ ! -f "$d/project-v1(1).zip" ]]
    [[ -f "$d/.patchdir/project-v1(1).zip" ]]
    [[ $output == *'Retired ZIP:   project-v1(1).zip'* ]]
}

run_test duplicate_existing_archive_suffix duplicate_existing_archive_suffix_test


new_archive_lifecycle_test() {
    local d="$TMP/new-archive-lifecycle" dl="$TMP/downloads-new-archive-lifecycle" new="$TMP/new-new-archive-lifecycle"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf oldzip > "$d/project-v1.zip"
    printf new > "$new/a"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
[[ -f ../downloads-new-archive-lifecycle/project-v2.zip ]] 2>/dev/null || true
[[ -f project-v2.zip ]] && exit 41
[[ -f "$PWD/../downloads-new-archive-lifecycle/project-v2.zip" ]] || exit 42
printf setup-ran > setup.out
SH
    make_zip "$new" "$dl/project-v2.zip"
    (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes >/dev/null)
    [[ -f "$d/project-v2.zip" ]]
    [[ ! -f "$dl/project-v2.zip" ]]
    [[ -f "$d/.patchdir/project-v1.zip" ]]

    printf newer > "$new/a"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
exit 23
SH
    make_zip "$new" "$dl/project-v3.zip"
    if (cd "$d" && "$BIN" "$dl/project-v3.zip" --yes >/dev/null 2>&1); then
        return 1
    fi
    [[ -f "$dl/project-v3.zip" ]]
    [[ ! -f "$d/project-v3.zip" ]]
}

run_test new_archive_lifecycle new_archive_lifecycle_test

multiple_historical_archives_test() {
    local d="$TMP/multiple-historical" dl="$TMP/downloads-multiple-historical" new="$TMP/new-multiple-historical" output
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf v13 > "$d/librarian-v0.4.13.zip"
    printf v15 > "$d/librarian-v0.4.15.zip"
    printf new > "$new/a"
    make_zip "$new" "$dl/librarian-v0.4.16.zip"
    output=$(cd "$d" && "$BIN" "$dl/librarian-v0.4.16.zip" --yes --no-setup --no-test)
    [[ $(cat "$d/a") == new ]]
    [[ -f "$d/librarian-v0.4.16.zip" ]]
    [[ -f "$d/librarian-v0.4.13.zip" ]]
    [[ ! -f "$d/librarian-v0.4.15.zip" ]]
    [[ $(cat "$d/.patchdir/librarian-v0.4.15.zip") == v15 ]]
    [[ $output != *'multiple possible old project archives'* ]]
}

run_test multiple_historical_archives multiple_historical_archives_test
run_test version_suffix version_suffix_test




nested_wrapper_project_root_test() {
    local d="$TMP/nested-wrapper" dl="$TMP/downloads-nested-wrapper" src="$TMP/nested-wrapper-src" output
    mkdir -p "$d" "$dl" "$src/patchzip/tests"
    printf '#!/usr/bin/env bash\nprintf new-patchzip\n' > "$src/patchzip/patchzip"
    chmod +x "$src/patchzip/patchzip"
    printf 'new-file\n' > "$src/patchzip/file.txt"
    printf 'test\n' > "$src/patchzip/tests/example"
    printf '# old executable\n' > "$d/patchzip"
    chmod +x "$d/patchzip"
    (cd "$src" && zip -qr "$dl/patchzip-v-0.4.19.zip" patchzip)
    output=$(cd "$d" && "$BIN" "$dl/patchzip-v-0.4.19.zip" --yes --no-setup --no-test)
    [[ -x "$d/patchzip" ]]
    [[ $(cat "$d/patchzip") == $'#!/usr/bin/env bash\nprintf new-patchzip\n' ]]
    [[ $(cat "$d/file.txt") == 'new-file' ]]
    [[ -f "$d/tests/example" ]]
    [[ ! -d "$d/patchzip" ]]
    [[ $output == *'Layout:        nested (patchzip/)'* ]]
}

run_test nested_wrapper_project_root nested_wrapper_project_root_test

hook_permissions_test() {
    local d="$TMP/hook-perms" dl="$TMP/downloads-hook-perms" new="$TMP/new-hook-perms"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    printf '#!/usr/bin/env bash\nprintf setup-ran > setup.out\n' > "$new/setup.sh"
    printf '#!/usr/bin/env bash\nprintf test-ran > test.out\n' > "$new/run_tests.sh"
    printf '#!/usr/bin/env bash\nprintf legacy-test-ran > legacy-test.out\n' > "$new/run_test.sh"
    chmod 644 "$new/setup.sh" "$new/run_tests.sh" "$new/run_test.sh"
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes >/dev/null)
    [[ -x "$d/setup.sh" ]]
    [[ -x "$d/run_tests.sh" ]]
    [[ -x "$d/run_test.sh" ]]
    [[ -f "$d/test.out" ]]
}

run_test hook_permissions hook_permissions_test

already_executable_hook_test() {
    local d="$TMP/already-executable-hook" dl="$TMP/downloads-already-executable-hook" new="$TMP/new-already-executable-hook"
    mkdir -p "$d" "$dl" "$new"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$new/run_test.sh"
    chmod 751 "$new/run_test.sh"
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup >/dev/null)
    [[ $(stat -c '%a' "$d/run_test.sh") == 751 ]]
}

run_test already_executable_hook already_executable_hook_test

dry_run_hook_permissions_test() {
    local d="$TMP/dry-hook-perms" dl="$TMP/downloads-dry-hook-perms" new="$TMP/new-dry-hook-perms"
    mkdir -p "$d" "$dl" "$new"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$new/run_tests.sh"
    chmod 644 "$new/run_tests.sh"
    make_zip "$new" "$dl/project-v1.zip"
    (cd "$d" && "$BIN" --dry-run "$dl/project-v1.zip" --yes --no-setup >/dev/null)
    [[ ! -e "$d/run_tests.sh" ]]
}

run_test dry_run_hook_permissions dry_run_hook_permissions_test

patchdir_backup_test() {
    local d="$TMP/patchdir" dl="$TMP/downloads-patchdir" new="$TMP/new-patchdir"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf old-zip > "$d/project-v1.zip"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test >/dev/null)
    [[ -f "$d/.patchdir/project-v1.zip" ]]
    [[ $(cat "$d/.patchdir/project-v1.zip") == old-zip ]]
    [[ ! -f "$d/project-v1.zip" ]]
    old_backup_sha=$(sha256sum "$d/.patchdir/project-v1.zip" | awk '{print $1}')
    printf newer > "$new/a"
    make_zip "$new" "$dl/project-v3.zip"
    (cd "$d" && "$BIN" "$dl/project-v3.zip" --yes --no-setup --no-test >/dev/null)
    [[ ! -f "$d/.patchdir/project-v1.zip" ]]
    [[ -f "$d/.patchdir/project-v2.zip" ]]
    new_backup_sha=$(sha256sum "$d/.patchdir/project-v2.zip" | awk '{print $1}')
    [[ $new_backup_sha != "$old_backup_sha" ]]
    [[ -f "$d/project-v3.zip" ]]
    [[ ! -f "$d/project-v2.zip" ]]
}

run_test patchdir_backup patchdir_backup_test


patchdir_waits_for_hooks_test() {
    local d="$TMP/patchdir-waits-for-hooks" dl="$TMP/downloads-patchdir-waits" new="$TMP/new-patchdir-waits"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf old-zip > "$d/project-v1.zip"
    printf new > "$new/a"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
[[ -f project-v1.zip ]]
printf setup-ran > setup.out
SH
    make_zip "$new" "$dl/project-v2.zip"
    (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes >/dev/null)
    [[ -f "$d/setup.out" ]]
    [[ ! -f "$d/project-v1.zip" ]]
    [[ -f "$d/.patchdir/project-v1.zip" ]]
    [[ $(cat "$d/.patchdir/project-v1.zip") == old-zip ]]
}

run_test patchdir_waits_for_hooks patchdir_waits_for_hooks_test

patchdir_retained_on_hook_failure_test() {
    local d="$TMP/patchdir-hook-failure" dl="$TMP/downloads-patchdir-hook-failure" new="$TMP/new-patchdir-hook-failure"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf old-zip > "$d/project-v1.zip"
    printf new > "$new/a"
    cat > "$d/setup.sh" <<'SH'
#!/usr/bin/env bash
exit 23
SH
    make_zip "$new" "$dl/project-v2.zip"
    if (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes >/dev/null 2>&1); then
        return 1
    fi
    [[ -f "$d/project-v1.zip" ]]
    [[ -f "$d/project-v2.zip" ]]
    [[ ! -e "$d/.patchdir/project-v1.zip" ]]
}

run_test patchdir_retained_on_hook_failure patchdir_retained_on_hook_failure_test

patchdir_backup_failure_test() {
    local d="$TMP/patchdir-failure" dl="$TMP/downloads-patchdir-failure" new="$TMP/new-patchdir-failure"
    mkdir -p "$d/.patchdir/previous-version.zip" "$dl" "$new"
    printf old > "$d/a"
    printf old-zip > "$d/project-v1.zip"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    ! (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test >/dev/null 2>&1)
    [[ -f "$d/project-v1.zip" ]]
    [[ -d "$d/.patchdir/previous-version.zip" ]]
}

run_test patchdir_backup_failure patchdir_backup_failure_test

patchdir_dry_run_test() {
    local d="$TMP/patchdir-dry-run" dl="$TMP/downloads-patchdir-dry-run" new="$TMP/new-patchdir-dry-run"
    mkdir -p "$d/.patchdir" "$dl" "$new"
    printf previous > "$d/.patchdir/project-v1.zip"
    printf old-zip > "$d/project-v1.zip"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    (cd "$d" && "$BIN" --dry-run "$dl/project-v2.zip" --yes --no-setup --no-test >/dev/null)
    [[ $(cat "$d/.patchdir/project-v1.zip") == previous ]]
    [[ -f "$d/project-v1.zip" ]]
}

run_test patchdir_dry_run patchdir_dry_run_test

non_versioned_backup_test() {
    local d="$TMP/patchdir-fallback" dl="$TMP/downloads-patchdir-fallback" new="$TMP/new-patchdir-fallback"
    mkdir -p "$d" "$dl" "$new"
    printf old > "$d/a"
    printf old-zip > "$d/project-1.zip"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-2.zip"
    (cd "$d" && "$BIN" "$dl/project-2.zip" --yes --no-setup --no-test >/dev/null)
    [[ -f "$d/.patchdir/previous-version.zip" ]]
    [[ $(cat "$d/.patchdir/previous-version.zip") == old-zip ]]
    [[ ! -f "$d/project-1.zip" ]]
}

run_test non_versioned_backup non_versioned_backup_test

hook_output_is_not_recolored_test() {
    local d="$TMP/hook-output" dl="$TMP/downloads-hook-output" new="$TMP/new-hook-output" output
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    cat > "$new/run_tests.sh" <<'SH'
#!/usr/bin/env bash
printf '\033[35mHOOK-OUTPUT\033[0m\n'
SH
    make_zip "$new" "$dl/project-v1.zip"
    output=$(cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup 2>&1)
    [[ $output == *$'\033[35mHOOK-OUTPUT\033[0m'* ]]
}

run_test hook_output_is_not_recolored hook_output_is_not_recolored_test

color_plain_output_test() {
    local d="$TMP/colors" dl="$TMP/downloads-colors" new="$TMP/new-colors" output
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v1.zip"
    output=$(cd "$d" && "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test)
    [[ $output != *$'\033['* ]]
    rm -f "$d/project-v1.zip"
    rm -rf "$d/.patchdir"
    output=$(cd "$d" && NO_COLOR=1 "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test 2>&1)
    [[ $output != *$'\033['* ]]
}

run_test color_plain_output color_plain_output_test

color_terminal_test() {
    local d="$TMP/colors-tty" dl="$TMP/downloads-colors-tty" new="$TMP/new-colors-tty"
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v1.zip"
    cp "$dl/project-v1.zip" "$d/project-v1.zip"
    PATCHZIP_BIN="$BIN" TEST_PROJECT="$d" TEST_ARCHIVE="$d/project-v1.zip" python3 - <<'PYTEST'
import os, pty, select

def run(env_extra):
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(os.environ['TEST_PROJECT'])
        env = os.environ.copy()
        env.update(env_extra)
        os.execve(os.environ['PATCHZIP_BIN'], [os.environ['PATCHZIP_BIN'], os.environ['TEST_ARCHIVE'], '--yes', '--no-setup', '--no-test'], env)
    buf = b''
    while True:
        ready, _, _ = select.select([fd], [], [], 5)
        if not ready:
            os.kill(pid, 9)
            raise SystemExit('timed out waiting for patchzip')
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        buf += chunk
    _, status = os.waitpid(pid, 0)
    if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
        raise SystemExit('patchzip failed in PTY')
    return buf

if b'\x1b[' not in run({}):
    raise SystemExit('expected ANSI color in TTY output')
if b'\x1b[' in run({'NO_COLOR': '1'}):
    raise SystemExit('NO_COLOR=1 did not suppress ANSI color')
if b'\x1b[' in run({'NO_COLOR': 'anything'}):
    raise SystemExit('non-empty NO_COLOR did not suppress ANSI color')
if b'\x1b[' not in run({'NO_COLOR': ''}):
    raise SystemExit('empty NO_COLOR unexpectedly suppressed TTY color')
PYTEST
}

run_test color_terminal color_terminal_test

report_status_colors_test() {
    local d="$TMP/report-colors" dl="$TMP/downloads-report-colors" new="$TMP/new-report-colors" output
    mkdir -p "$d" "$dl" "$new"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v1.zip"
    cp "$dl/project-v1.zip" "$d/project-v1.zip"

    output=$(cd "$d" && NO_COLOR= bash -c '[[ -t 1 ]] || exit 0; exec "$@"' _ "$BIN" "$dl/project-v1.zip" --yes --no-setup --no-test)
    # Report colors are covered below in a real PTY so stdout is color-enabled.
    PATCHZIP_BIN="$BIN" TEST_PROJECT="$d" TEST_ARCHIVE="$dl/project-v1.zip" python3 - <<'PYTEST'
import os, pty, select

pid, fd = pty.fork()
if pid == 0:
    os.chdir(os.environ['TEST_PROJECT'])
    env = os.environ.copy()
    os.execve(os.environ['PATCHZIP_BIN'], [os.environ['PATCHZIP_BIN'], os.environ['TEST_ARCHIVE'], '--yes', '--no-setup', '--no-test'], env)
buf = b''
while True:
    ready, _, _ = select.select([fd], [], [], 5)
    if not ready:
        os.kill(pid, 9)
        raise SystemExit('timed out waiting for patchzip')
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    buf += chunk
_, status = os.waitpid(pid, 0)
if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
    raise SystemExit('patchzip failed in PTY')
# With --no-setup/--no-test, only Result is a success; not-run statuses must remain unstyled.
if b'\x1b[32mnot run' in buf or b'\x1b[31mnot run' in buf:
    raise SystemExit('not-run status was colored')
if b'\x1b[32msuccess\x1b[0m' not in buf:
    raise SystemExit('successful Result was not colored green')
PYTEST
}

run_test report_status_colors report_status_colors_test

git_mode_test() {
    local d="$TMP/git-mode" dl="$TMP/downloads-git-mode" new="$TMP/new-git-mode"
    mkdir -p "$d" "$dl" "$new"
    (cd "$d" && git init -q && git config user.email test@example.invalid && git config user.name Test)
    printf old > "$d/a"
    (cd "$d" && git add a && git commit -qm initial)
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test --git >/dev/null)
    [[ $(cd "$d" && git branch --show-current) == patchzip/project-v2 ]]
    [[ $(cd "$d" && git log -1 --pretty=%s) == 'Apply project-v2.zip' ]]
    [[ $(cat "$d/a") == new ]]
    [[ -f "$d/project-v2.zip" ]]
}

run_test git_mode git_mode_test

git_mode_existing_branch_test() {
    local d="$TMP/git-existing-branch" dl="$TMP/downloads-git-existing-branch" new="$TMP/new-git-existing-branch"
    mkdir -p "$d" "$dl" "$new"
    (cd "$d" && git init -q && git config user.email test@example.invalid && git config user.name Test)
    printf old > "$d/a"
    (cd "$d" && git add a && git commit -qm initial && git branch patchzip/project-v2)
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    ! (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test --git >/dev/null 2>&1)
    [[ $(cd "$d" && git branch --show-current) == master || $(cd "$d" && git branch --show-current) == main ]]
    [[ $(cat "$d/a") == old ]]
}

run_test git_mode_existing_branch git_mode_existing_branch_test

git_mode_patchdir_excluded_test() {
    local d="$TMP/git-patchdir" dl="$TMP/downloads-git-patchdir" new="$TMP/new-git-patchdir"
    mkdir -p "$d" "$dl" "$new"
    (cd "$d" && git init -q && git config user.email test@example.invalid && git config user.name Test)
    printf old > "$d/a"
    printf previous-archive > "$d/project-v1.zip"
    (cd "$d" && git add a project-v1.zip && git commit -qm initial)
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test --git >/dev/null)
    [[ -f "$d/.patchdir/project-v1.zip" ]]
    [[ $(cd "$d" && git ls-tree -r --name-only HEAD | grep -c '^\.patchdir/') -eq 0 ]]
    [[ $(cd "$d" && git status --porcelain) == *'.patchdir/'* ]]
}

run_test git_mode_patchdir_excluded git_mode_patchdir_excluded_test

git_mode_invalid_branch_test() {
    local d="$TMP/git-invalid-branch" dl="$TMP/downloads-git-invalid-branch" new="$TMP/new-git-invalid-branch"
    mkdir -p "$d" "$dl" "$new"
    (cd "$d" && git init -q && git config user.email test@example.invalid && git config user.name Test)
    printf old > "$d/a"
    (cd "$d" && git add a && git commit -qm initial)
    printf new > "$new/a"
    make_zip "$new" "$dl/project..bad-v1.zip"
    ! (cd "$d" && "$BIN" "$dl/project..bad-v1.zip" --yes --no-setup --no-test --git >/dev/null 2>&1)
    [[ $(cat "$d/a") == old ]]
}

run_test git_mode_invalid_branch git_mode_invalid_branch_test

git_mode_dirty_test() {
    local d="$TMP/git-dirty" dl="$TMP/downloads-git-dirty" new="$TMP/new-git-dirty"
    mkdir -p "$d" "$dl" "$new"
    (cd "$d" && git init -q && git config user.email test@example.invalid && git config user.name Test)
    printf old > "$d/a"
    (cd "$d" && git add a && git commit -qm initial)
    printf dirty > "$d/a"
    printf new > "$new/a"
    make_zip "$new" "$dl/project-v2.zip"
    ! (cd "$d" && "$BIN" "$dl/project-v2.zip" --yes --no-setup --no-test --git >/dev/null 2>&1)
    [[ $(cd "$d" && git branch --show-current) == master || $(cd "$d" && git branch --show-current) == main ]]
    [[ $(cat "$d/a") == dirty ]]
}

run_test git_mode_requires_clean_tree git_mode_dirty_test

install_test() {
    local home="$TMP/install-home" pathdir="$TMP/install-path"
    rm -rf "$home" "$pathdir"
    mkdir -p "$home" "$pathdir"
    HOME="$home" PATH="/usr/bin:/bin" bash "$ROOT/install.sh" >/tmp/patchzip-install-output
    [[ -L "$home/.local/bin/patchzip" ]]
    [[ $(readlink -f "$home/.local/bin/patchzip") == "$(readlink -f "$ROOT/patchzip")" ]]
    [[ -L "$home/.local/bin/pzip" ]]
    [[ $(readlink "$home/.local/bin/pzip") == patchzip ]]
    [[ $(HOME="$home" "$home/.local/bin/patchzip" --version) == 0.4.24 ]]
}

run_test user_local_install install_test

install_alias_collision_test() {
    local home="$TMP/install-collision-home" pathdir="$TMP/install-collision-path"
    rm -rf "$home" "$pathdir"
    mkdir -p "$home/.local/bin" "$pathdir"
    printf '#!/usr/bin/env bash\nexit 23\n' > "$pathdir/pzip"
    chmod +x "$pathdir/pzip"
    HOME="$home" PATH="$pathdir:/usr/bin:/bin" bash "$ROOT/install.sh" >/tmp/patchzip-install-collision-output
    [[ -L "$home/.local/bin/patchzip" ]]
    [[ $(readlink -f "$home/.local/bin/patchzip") == "$(readlink -f "$ROOT/patchzip")" ]]
    [[ ! -e "$home/.local/bin/pzip" ]]
    [[ $("$pathdir/pzip"; echo $?) == 23 ]]
}

run_test user_local_install_preserves_existing_pzip install_alias_collision_test

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))

# patchzip

`patchzip` is a safe project patcher that lets coding agents deliver ZIP patches without direct access to your computer.

## Why?

The coding agent and your environment stay separated by a deliberate boundary: **you**.

The agent prepares a release ZIP. You run one command:

```bash
pzip project-v-1.2.3.zip
```

`patchzip` validates it, applies it to the project, runs the project's setup/tests, and reports the result. The agent never needs access to your filesystem, shell, or computer.

This is especially useful when your AI service cannot access your computer, such as without a premium computer-use feature, or when you simply do not want to grant an agent that access.

## Usage

From the project directory:

```bash
patchzip path/to/project-v-0.2.zip
```

By default, patchzip asks before changing anything. For scripts or automation:

```bash
patchzip --yes path/to/project-v-0.2.zip
```

Release archives should use `<project>-v-<version>.zip`, for example `project-v-0.8.13.zip`. The older `<project>-v<version>.zip` form is still accepted, as are descriptive suffixes such as `project-v0.8.13-reconstructed.zip`.

If no archive is supplied, patchzip can select an obvious matching archive from `~/Downloads`.

Useful options:

```text
-y, --yes       Apply without asking
-n, --dry-run   Show what would happen without changing anything
    --no-setup  Do not run setup.sh
    --no-test   Do not run the project test hook
    --git       After hooks pass, create a branch, commit the patch, and push it
-h, --help      Show help
    --version   Show version
```

## Instructions for your coding agent

If an AI coding agent maintains a project using patchzip, store these rules in its persistent project memory:

> **Patchzip compatibility**
>
> > - Deliver releases as `<project>-v-<version>.zip`.
> > - Put files at their project-root paths; do not add an enclosing release directory.
> > - The user applies releases with `patchzip`/`pzip`; do not instruct them to manually unzip files.
> > - Keep `setup.sh` and the project test hook authoritative.
> > - Keep releases clean: no generated archives, caches, or unrelated build files.
> > - Keep patchzip integration simple and deterministic.

## The patch

Archives are applied at the project root. They may contain the project files directly or one top-level directory matching the project name.

Before changing the project, patchzip validates the archive and rejects unsafe paths and symbolic links. Files in the project that are not in the patch are left alone.

If the project contains `setup.sh`, `run_tests.sh`, or `run_test.sh`, patchzip can run the appropriate hooks after applying the patch. If `setup.sh` invokes the configured test hook itself, patchzip detects that invocation through a temporary internal marker and does not run the hook a second time. The marker is removed during cleanup. Their output is passed through unchanged; patchzip does not try to detect or manage arbitrary test frameworks.

Before changing the project, patchzip validates the archive. It then shows the upgrade transition immediately before the existing confirmation point, using only version information that is actually available. If the incoming archive's project name differs from the target directory name, it also prints a prominent factual mismatch warning; the warning does not alter archive selection or application behavior.

The input release ZIP remains in its original location (normally `~/Downloads`) until all configured hooks have completed successfully. If a configured hook fails, the input ZIP is discarded because the project has already been modified and the failed archive is not retained as a rerun candidate. On success, the new ZIP is moved into the project root, and older matching versioned release ZIPs still in `~/Downloads` are removed as stale inputs. Same-version duplicates and unrelated ZIPs are left alone. Existing release ZIPs are treated as historical archives rather than competing inputs: when several versions are present, the highest matching version is retired into `.patchdir/`. Browser download suffixes such as `(1)` are ignored when identifying versions, while the actual filename is preserved when an archive is retired.

With `--git`, the project must be the root of a clean Git worktree with an `origin` remote. The derived target branch must not already exist locally **or on `origin`**. Git finalization is deliberately deferred until **all configured hooks have passed**. Only then does patchzip create `patchzip/<archive-stem>` with `git switch -c`, stage all changes except `.patchdir`, commit with `Apply <archive>`, and run `git push -u origin <branch>`. Git authentication and prompts are handled by native Git. A failed hook creates no branch or commit; a commit failure leaves the local branch intact; and a push failure leaves the local branch and commit intact so the push can be retried manually. `--dry-run` never creates, stages, commits, or pushes Git state.

## Installation

```bash
./install.sh
```

The installer creates `patchzip` and `pzip` symlinks in `~/.local/bin` and does not require `sudo` or modify shell startup files.

## Requirements

GNU/Linux, Bash 4.4+, and:

- `unzip`
- `zipinfo`
- `cmp`
- `git` for `--git`

The test suite additionally uses `zip`, `sha256sum`, and Python 3.

## Testing

```bash
bash tests/test_patchzip.sh
```

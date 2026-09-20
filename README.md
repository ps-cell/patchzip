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

Archives are applied at the project root (or from one matching top-level directory). Before changing anything, patchzip validates the archive, rejects unsafe paths and symbolic links, and leaves files not included in the patch untouched.

After applying the patch, patchzip can run `setup.sh` and the project test hook (`run_tests.sh` or `run_test.sh`). If `setup.sh` invokes that test hook itself, patchzip detects it and avoids running it twice. Hook output is passed through unchanged.

The input ZIP is retained until all hooks succeed; a failed hook discards it, while a successful run moves it into the project root and cleans up stale matching downloads. Older matching releases are retired into `.patchdir/`. With `--git`, Git finalization happens only after the hooks pass: patchzip creates a new branch, stages the project changes except `.patchdir`, commits, and pushes it. Failures leave existing Git state recoverable, and `--dry-run` makes no Git changes.

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

# patchzip

`patchzip` is a safe project patcher that lets coding agents deliver ZIP patches without direct access to your computer.

## Why?

The coding agent and your environment stay separated by a deliberate boundary: **you**.

The agent prepares a release ZIP. You run one command:

```bash
cd /path/to/your/project
pzip
```

When you run without any arguments `patchzip` tries to automatically find a fitting archive in your `~/Downloads`, based on the name of `pwd` and the found `*.zip` files. 

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

Release archives should use `<project>-v-<version>.zip`, for example `project-v-0.8.13.zip`. The older `<project>-v<version>.zip` form is still accepted.

If no archive is supplied, patchzip can select an obvious matching archive from `~/Downloads`.

Useful options:

```text
-y, --yes       Apply without asking
-n, --dry-run   Show what would happen without changing anything
    --no-setup  Do not run setup.sh
    --no-test   Do not run the project test hook
    --git       Apply the patch on a new Git branch and commit it
-h, --help      Show help
    --version   Show version
```

## The patch

Archives are applied at the project root. They may contain the project files directly or one top-level directory matching the project name.

Before changing the project, patchzip validates the archive and rejects unsafe paths and symbolic links. Files in the project that are not in the patch are left alone.

If the project contains `setup.sh`, `run_tests.sh`, or `run_test.sh`, patchzip can run the appropriate hooks after applying the patch. Their output is passed through unchanged; patchzip does not try to detect or manage arbitrary test frameworks.

When an older project release ZIP is replaced successfully, patchzip keeps it in `.patchdir/` as a local backup.

## Instructions for your coding agent

If an AI coding agent maintains a project using patchzip, store these rules in its persistent project memory:

> **Patchzip compatibility**
>
> > - Deliver releases as `<project>-v-<version>.zip`.
> > - Put files at their project-root paths; do not add an enclosing release directory.
> > - The user applies releases with `patchzip`/`pzip`; do not instruct them to manually unzip files.
> > - Keep `setup.sh` and the project test hook `run_tests.sh` authoritative.
> > - Keep releases clean: no generated archives, caches, or unrelated build files.

## Installation

```bash
./install.sh
```

The installer creates `patchzip` and `pzip` symlinks in `~/.local/bin` and does not require `sudo` or modify shell startup files.

## Requirements

GNU/Linux, Bash 4+, and:

- `unzip`
- `zipinfo`
- `cmp`
- `git` for `--git`

The test suite additionally uses `zip`, `sha256sum`, and Python 3.

## Testing

```bash
bash tests/test_patchzip.sh
```

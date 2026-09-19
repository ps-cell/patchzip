#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
BIN_DIR=${HOME}/.local/bin
TARGET=${BIN_DIR}/patchzip
ALIAS=${BIN_DIR}/pzip

[[ -f ${ROOT}/patchzip ]] || { printf 'install.sh: patchzip not found in %s\n' "$ROOT" >&2; exit 1; }
mkdir -p -- "$BIN_DIR"

ln -sfn -- "${ROOT}/patchzip" "$TARGET"

# Do not shadow an existing pzip command. If pzip already points at our installed
# patchzip, refresh it; otherwise leave it alone.
existing=''
if command -v pzip >/dev/null 2>&1; then
    existing=$(command -v pzip)
fi

if [[ -n $existing && $existing != "$ALIAS" ]]; then
    printf 'Installed patchzip to %s\n' "$TARGET"
    printf 'pzip already exists at %s; leaving it unchanged.\n' "$existing"
else
    ln -sfn -- patchzip "$ALIAS"
    printf 'Installed patchzip to %s\n' "$TARGET"
    printf 'Installed pzip -> patchzip in %s\n' "$BIN_DIR"
fi

if [[ :$PATH: != *:"$BIN_DIR":* ]]; then
    printf '\n%s is not currently in PATH.\n' "$BIN_DIR"
    printf 'Add it to your shell configuration if you want to run patchzip/pzip from anywhere:\n'
    printf '  export PATH="$HOME/.local/bin:$PATH"\n'
fi

#!/usr/bin/env bash
set -euo pipefail
binary="$1"

actual="$("$binary" --dry-run cmd+h ctrl+shift+a alt+enter 0 left)"
expected=$'validated cmd+h\nvalidated ctrl+shift+a\nvalidated alt+enter\nvalidated 0\nvalidated left'
[[ "$actual" == "$expected" ]]

actual="$(printf 'cmd+h\nenter\n' | "$binary" --dry-run --stdin)"
[[ "$actual" == $'ready\nvalidated cmd+h\nvalidated enter' ]]

[[ "$("$binary" --dry-run key cmd+h)" == 'validated cmd+h' ]]
[[ "$("$binary" --dry-run move relative -400 250)" == 'validated move' ]]
[[ "$("$binary" --dry-run move absolute -100 200 --smooth 0.5)" == 'validated move' ]]
[[ "$("$binary" --dry-run move percent 50 100 --smooth 0)" == 'validated move' ]]
actual="$(printf 'key cmd+h\nmove percent 50 50\n' | "$binary" --dry-run --stdin)"
[[ "$actual" == $'ready\nvalidated cmd+h\nvalidated move' ]]

for chord in '' cmd cmd+ +h cmd++h h+a unknown --unknown; do
    if "$binary" --dry-run "$chord" >/dev/null 2>&1; then
        printf 'Unexpectedly accepted chord: %s\n' "$chord" >&2
        exit 1
    fi
done
if "$binary" --dry-run --stdin cmd+h >/dev/null 2>&1; then
    echo 'Unexpectedly accepted positional keys with --stdin' >&2
    exit 1
fi
if printf '\n' | "$binary" --dry-run --stdin >/dev/null 2>&1; then
    echo 'Unexpectedly accepted an empty input line' >&2
    exit 1
fi
rule="$("$binary" --dry-run sudoer grant --user "$(id -un)")"
binary_path="$(cd "$(dirname "$binary")" && pwd -P)/$(basename "$binary")"
digest="$(shasum -a 256 "$binary_path" | cut -d' ' -f1)"
grep -qxF "$(id -un) ALL=(root) NOPASSWD: sha256:$digest $binary_path" <<<"$rule"
[[ "$("$binary" --dry-run sudoer grant)" == "$rule" ]]
[[ "$("$binary" --dry-run sudoer revoke)" == 'would remove /private/etc/sudoers.d/macos-input' ]]
if [[ "$(id -u)" != 0 ]]; then
    for command in grant revoke; do
        if "$binary" sudoer "$command" >/dev/null 2>&1; then
            echo "Unexpectedly ran $command without root" >&2
            exit 1
        fi
    done
fi
for bad in 'sudoer grant --user' 'sudoer grant --user root' 'sudoer grant --user no-such-user-xyz' \
    'sudoer grant --user a,b' 'sudoer revoke extra' 'sudoer' 'sudoer list'; do
    # shellcheck disable=SC2086
    if "$binary" --dry-run $bad >/dev/null 2>&1; then
        printf 'Unexpectedly accepted: %s\n' "$bad" >&2
        exit 1
    fi
done
echo 'CLI validation and streaming tests passed without keyboard input.'

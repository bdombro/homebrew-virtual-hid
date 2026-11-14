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
echo 'CLI validation and streaming tests passed without keyboard input.'

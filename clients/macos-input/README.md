# macos-input

A CLI client for the [virtual-hid driver](../../docs/driver.md). It presses key chords and moves the mouse through the driver's virtual keyboard and mouse.

```text
macos-input [--dry-run] key CHORD [CHORD ...]
macos-input [--dry-run] move relative|absolute|percent X Y [--smooth SECONDS]
macos-input [--dry-run] --stdin
macos-input --version
```

Live input needs the `virtual-hid-driver` cask with its daemon running, and either sudo or membership in the `virtual-hid` group (see [Group access](../../docs/driver.md#group-access)). Input affects whichever app is focused. Checking the front app before sending input isn't an atomic focus lock.

## Keys

A chord is one key plus optional modifiers: `cmd`, `ctrl`, `shift`, `alt`/`option`, joined with `+`. Each chord presses, then releases.

Keys:

- lowercase letters and digits;
- `enter`, `escape`, `backspace`, `tab`, `space`, `delete`;
- `minus`, `equal`, `left-bracket`, `right-bracket`, `backslash`, `semicolon`, `quote`, `grave`, `comma`, `period`, `slash`;
- `left`, `right`, `up`, `down`.

## Mouse

- **`relative X Y`**: signed integer HID counts, split into the driver's -127..127 report range. Mouse acceleration affects the on-screen distance.
- **`absolute X Y`**: global macOS screen points with a top-left origin. Secondary displays can have negative coordinates. The target must lie on an active display.
- **`percent X Y`**: 0-100 on the display that contains the cursor when the command starts. 0 and 100 map to the first and last screen point, not past the edge.

Movement isn't animated by default. `--smooth SECONDS` adds ease-in/out interpolation; `--smooth 0` is the same as no animation. Smoothing is best effort, not a real-time timing guarantee.

Absolute and percent moves read the cursor position as they go to compensate for acceleration:

- each axis may end up to 0.5 points off;
- the move fails after five seconds of correction beyond the requested duration;
- some coordinates may be unreachable because of acceleration or display boundaries.

All movement goes through the driver. CoreGraphics only reads cursor and display geometry. There's no fallback to warping the cursor or injecting Quartz events.

## Stdin mode

`--stdin` keeps the virtual devices alive until EOF or Ctrl+C. It prints `ready`, then accepts one command per line, for example `key cmd+h` or `move percent 50 50`. It prints `ok` after each chord's press and release are acknowledged, or after each completed move. `ok` doesn't prove the focused app handled the input.

## Dry run, errors and exit codes

`--dry-run` validates syntax without root, the driver, screen reads or input. Errors go to stderr with a nonzero exit; Ctrl+C exits 130.

## Building from source

Targets macOS 13 Ventura or newer. Building requires CMake 3.31+, Ninja, just, vcpkg (`VCPKG_ROOT` set), `llvm@23` (`LLVM_BIN` defaults to `$(brew --prefix llvm@23)/bin`), and Xcode Command Line Tools (`xcrun` SDK). Build and install as your normal user, never with sudo.

```sh
just doctor
just test     # Debug build with ASan + UBSan
just build    # Release binary staged at build/bin/macos-input
```

From the repository root, `just test` and `just build` do the same.

The build uses C++26 with `llvm@23` Clang and static `libc++`, FAST hardening, sanitizers in Debug and LTO in Release. It's macOS-only and uses `slimr-test` from vcpkg plus CMake `FetchContent` for upstream's client headers, bundled dependencies and a small Objective-C autorelease-pool shim at the reviewed v8.8.0 commit `212a0f660702e33a3874895c4db991061e68e0e2` (protocol 7). Upstream's driver, packaging and project build scripts are not built or run.

See [distribution](../../docs/distribution.md) for Homebrew installs, just recipes and releases.

### Layout

```text
clients/macos-input/
  CMakeLists.txt                Debug/Release builds and tests
  src/main.cpp                  CLI, virtual devices and cursor-feedback movement
  src/mouse.hpp                 movement parsing, geometry and interpolation
  tests/cli.sh, test_main.cpp   no-input CLI and doctest mouse tests
  justfile                      configure, build, test, fmt, lint, doctor recipes
  resources/driver-setup.txt    driver setup guide shared by the CLI and formula
  vcpkg.json, triplets/         vcpkg manifest and overlay triplets
  build/                        ignored build output, deps and staged Release binary
VERSION                         release version, embedded in --version
CHANGELOG.md                    release notes
justfile                        tap recipes: install, driver daemon, group access; delegates build, test, release
scripts/                        CI release scripts (release.ts, formula-shared.ts) and driver-update.sh
Formula/, Casks/                Homebrew formula and driver cask (must stay at the root)
```

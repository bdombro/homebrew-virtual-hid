# macos-input

A CLI client for the [virtual-hid driver](driver.md). It presses key chords and moves the mouse through the driver's virtual keyboard and mouse.

```text
macos-input [--dry-run] key CHORD [CHORD ...]
macos-input [--dry-run] move relative|absolute|percent X Y [--smooth SECONDS]
macos-input [--dry-run] --stdin
macos-input --version
```

Live input needs the `virtual-hid-driver` cask with its daemon running, and either sudo or membership in the `virtual-hid` group (see [Group access](driver.md#group-access)). Input affects whichever app is focused. Checking the front app before sending input isn't an atomic focus lock.

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

Targets macOS 13 Ventura or newer. Building requires CMake 3.31+, Ninja, just, Bun and a recent Xcode command-line compiler with C++26 support. Build and install as your normal user, never with sudo.

```sh
just setup
just test
just build    # stages dist/macos-input
```

The build follows the sibling tool-env app's layout and just recipes: C++26 with Clang/libc++, warnings, FAST hardening, sanitizers in Debug and LTO in Release. It's macOS-only and uses no vcpkg packages.

CMake fetches upstream's client headers, bundled dependencies and a small Objective-C autorelease-pool shim at the reviewed v8.8.0 commit `212a0f660702e33a3874895c4db991061e68e0e2` (protocol 7). Upstream's driver, packaging and project build scripts are not built or run.

See [distribution](distribution.md) for local Homebrew installs, just recipes and releases.

### Layout

```text
clients/macos-input/src/main.cpp            CLI, virtual devices and cursor-feedback movement
clients/macos-input/src/mouse.hpp           movement parsing, geometry and interpolation
clients/macos-input/tests/cli.sh, mouse.cpp  no-input CLI and mouse tests
CMakeLists.txt, justfile                    Debug/Release builds, tests and explicit installation
VERSION, CHANGELOG.md                       application version and release notes
scripts/, Formula/, Casks/                  Homebrew CLI formula, driver cask and release tooling
dist/                                       ignored compiled executable and release zip
resources/driver-setup.txt                  driver setup guide shared by the CLI and formula
build/cmake/{Debug,Release}                 ignored build output and pinned dependency checkout
```

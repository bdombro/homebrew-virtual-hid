# macos-input

CLI for sending keyboard chords and mouse movement to macOS via virtual HID keyboard driver. Kinda like [ydotool](https://github.com/ReimuNotMoe/ydotool) for Linux.

## Layout

```text
src/main.cpp                 CLI, virtual devices and cursor-feedback movement
src/mouse.hpp                movement parsing, geometry and interpolation
tests/cli.sh, mouse.cpp      no-input CLI and mouse tests
CMakeLists.txt, justfile     Debug/Release builds, tests and explicit installation
VERSION, CHANGELOG.md        application version and release notes
scripts/, Formula/          Homebrew local install and public release tooling
dist/                       ignored compiled executable and release zip
build/cmake/{Debug,Release}  ignored build output and pinned dependency checkout
```

Follows the sibling tool-env app's layout, just recipes, C++26 Clang/libc++,
warnings, FAST hardening, Debug sanitizers and Release LTO. macOS-only;
no vcpkg packages. CMake fetches the upstream client headers, bundled
dependencies and small Objective-C autorelease-pool shim at reviewed v8.8.0
commit `212a0f660702e33a3874895c4db991061e68e0e2` (protocol 7).
Upstream's driver, packaging and project build scripts are not built or run.

## Build and validate

Targets macOS 13 Ventura or newer. Building requires CMake 3.31+, Ninja,
just, Bun and a recent Xcode command-line compiler with C++26 support.
Build and run Homebrew as your normal user, never with sudo.

```sh
just setup
just test
just install-local
```

Homebrew owns the installed executable; Bun is only development/release tooling.
`just reinstall-local` rebuilds and replaces it; `just uninstall` removes it.
`just build` only compiles and stages `dist/macos-input`.

After the first public release:

```sh
brew tap bdombro/macos-input https://github.com/bdombro/macos-input.git
brew install bdombro/macos-input/macos-input
```

Maintain `CHANGELOG.md` under `[Unreleased]`, then use
`just release minor --dry-run` or `just release minor` (asks before publishing).
`VERSION` starts at `0.0.0`, making the first minor release `0.1.0`.
See [distribution](docs/distribution.md) for tap setup, upgrades, supported
binary targets, release prerequisites, and recovery.

## Usage

```sh
macos-input --version
macos-input --dry-run key cmd+h
sudo macos-input key cmd+h ctrl+shift+a enter
sudo macos-input move relative 100 -50
sudo macos-input move absolute 500 300
sudo macos-input move percent 50 50 --smooth 0.5
sudo macos-input --stdin
```

Keys: one lowercase letter, digit or named key, plus optional `cmd`, `ctrl`,
`shift`, `alt`/`option`. Named keys: `enter`, `escape`, `backspace`, `tab`,
`space`, `minus`, `equal`, `left-bracket`, `right-bracket`, `backslash`,
`semicolon`, `quote`, `grave`, `comma`, `period`, `slash`, `delete`,
`left`, `right`, `up`, `down`. Each chord presses then releases.

Mouse modes:

- `relative X Y`: signed integer HID counts, split into the driver's
  -127..127 report range. Mouse acceleration affects screen distance.
- `absolute X Y`: global macOS screen points, top-left origin, including
  negative coordinates on secondary displays. Targets must lie on an active display.
- `percent X Y`: 0-100 on the display containing the cursor when the
  command starts. 0/100 map to the first/last screen point, not outside the edge.
- Movement has no animation by default. `--smooth SECONDS` adds ease-in/out
  interpolation; zero remains unanimated. Absolute modes use cursor feedback
  to compensate for acceleration, accept at most 0.5-point error per axis,
  and fail after five seconds of correction beyond the requested duration.
  Some coordinates may be unreachable because of acceleration or display boundaries.

All emitted movement uses the driver. CoreGraphics only reads cursor/display
geometry; there is no cursor-warp or Quartz-event injection fallback.
Smoothing is best effort, not a real-time timing guarantee.

`--stdin` keeps virtual devices alive until EOF/Ctrl+C, prints `ready`, and
accepts one command per line (for example `key cmd+h` or `move percent 50 50`).
It prints `ok` after each chord's press/release responses or completed move;
this does not prove a foreground app handled the input.
`--dry-run` validates syntax without root, driver, screen reads or input.
Errors go to stderr and exit nonzero; Ctrl+C exits 130.

## Driver and permissions

Live operation needs the separately installed/approved
[Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)
driver and its running root daemon. This CLI never installs, activates or
starts them. Root is required by that daemon's socket-access policy, not by
our build or app-launch code. No developer-certificate signing or launchd
registration is required for this foreground client. Driver signing and
system-extension approval remain separate requirements.

Input affects whichever app is focused. Caller-side app checks are not an
atomic focus lock. Idle-timer resets, auto-lock prevention and real pointer
precision remain unverified until authorized testing with the driver.

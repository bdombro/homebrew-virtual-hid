# macos-input

CLI for sending keyboard chords and mouse movement to macOS via virtual HID keyboard driver. Kinda like [ydotool](https://github.com/ReimuNotMoe/ydotool) for Linux.

## Layout

```text
src/main.cpp                 CLI, virtual devices and cursor-feedback movement
src/mouse.hpp                movement parsing, geometry and interpolation
tests/cli.sh, mouse.cpp      no-input CLI and mouse tests
CMakeLists.txt, justfile     Debug/Release builds, tests and explicit installation
VERSION, CHANGELOG.md        application version and release notes
scripts/, Formula/, Casks/  Homebrew CLI formula, driver cask and release tooling
dist/                       ignored compiled executable and release zip
build/cmake/{Debug,Release}  ignored build output and pinned dependency checkout
```

Follows the sibling tool-env app's layout, just recipes, C++26 Clang/libc++, warnings, FAST hardening, Debug sanitizers and Release LTO. macOS-only; no vcpkg packages. CMake fetches the upstream client headers, bundled dependencies and small Objective-C autorelease-pool shim at reviewed v8.8.0 commit `212a0f660702e33a3874895c4db991061e68e0e2` (protocol 7). Upstream's driver, packaging and project build scripts are not built or run.

## Build and validate

Targets macOS 13 Ventura or newer. Building requires CMake 3.31+, Ninja, just, Bun and a recent Xcode command-line compiler with C++26 support. Run builds and Homebrew installs as your normal user; live input needs sudo or membership in the `virtual-hid` group.

```sh
just setup
just test
just install-local
```

Homebrew owns the installed executable; Bun is only development/release tooling. `install-local` links this checkout as the `bdombro/virtual-hid` tap and installs its cask and formula, but the formula downloads the latest released CLI binary, not `dist/`. `install-local` and `install-github` first run `uninstall`, which removes `macos-input`, the `virtual-hid-driver` cask and the tap directory. `status` and the `driver-*` recipes run `sudo launchctl` and prompt for a password. GUI approval remains manual.

- `just install-local`: clean-install the driver and macos-input from this checkout's cask/formula (CLI binary is the latest release)
- `just install-github`: clean-install the driver and macos-input exactly as users do, from GitHub main
- `just uninstall`: remove macos-input, the driver (and its daemon), and the tap
- `just status`: show driver activation state and whether the root daemon is loaded
- `just driver-start`: enable and start the driver daemon (persists across reboots)
- `just driver-stop`: stop and disable the driver daemon so it stays off after reboot
- `just driver-restart`: restart the driver daemon

`just build` only compiles and stages `dist/macos-input`. Installs do not run tests; use `just test` or `brew test bdombro/virtual-hid/macos-input` explicitly.

Public installation:

```sh
brew tap bdombro/virtual-hid
brew trust bdombro/virtual-hid
brew install --cask virtual-hid-driver
brew install macos-input
```

### Migrating from the old tap

If you installed from the old `bdombro/macos-input` tap, first uninstall the old formula, trust the old tap (newer Homebrew refuses to touch casks from untrusted taps) and uninstall the old driver cask (this stops and removes the old daemon and deactivates the driver), then untap, then run the install block above. macOS may ask you to approve the driver again.

```sh
brew uninstall macos-input
brew trust bdombro/macos-input
brew uninstall --cask karabiner-driverkit-virtualhiddevice
brew untap bdombro/macos-input
```

### Releasing

Maintain `CHANGELOG.md` under `[Unreleased]`, then use `just release minor --dry-run` or `just release minor` (asks before publishing). `VERSION` starts at `0.0.0`, making the first minor release `0.1.0`. See [distribution](docs/distribution.md) for tap setup, upgrades, supported binary targets, release prerequisites, and recovery.

## Driver setup (required for live input)

This tool depends on the open-source, Developer ID-signed and Apple-notarized [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) driver, pinned to [v8.8.0](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v8.8.0). Signing/notarization is not a guarantee of harmlessness.

Complete these steps in order. Skip any steps you have already completed. `just install-local` and `just install-github` install the cask; you still need to complete macOS approval.

1. **Tap, trust and install the driver cask as your normal user.** Homebrew verifies the download and requests administrator authentication for macOS Installer. The cask requests activation and installs its own root LaunchDaemon (`com.github.bdombro.virtual-hid-driver.daemon`).

   ```sh
   brew tap bdombro/virtual-hid
   brew trust bdombro/virtual-hid
   brew install --cask virtual-hid-driver
   ```

2. **Approve the driver** when macOS prompts. If you clicked OK or the popup disappeared, open System Settings > General > Login Items & Extensions, click "By Category", click ⓘ next to "Driver Extensions", and turn on `.Karabiner-VirtualHIDDevice-Manager.app` (`org.pqrs.Karabiner-DriverKit-VirtualHIDDevice`). On older macOS versions, check Privacy & Security. Restart if requested. If no prompt appeared, request activation manually as your logged-in user, without sudo:

   ```sh
   /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
   ```

3. **Check the daemon** if live input reports a missing socket:

   ```sh
   sudo launchctl print system/com.github.bdombro.virtual-hid-driver.daemon
   ```

The formula is CLI-only; Homebrew caveats print the shared [setup guide](resources/driver-setup.txt) only while the driver is missing. Live commands without the driver exit non-zero and print the same guide; they never install, start or prompt for anything.

The install and uninstall recipes run plain Homebrew commands with inherited terminal input/output and stop at the first failing command, except the `|| true` uninstall steps, which tolerate a package that is not installed.

To remove the driver, run:

```sh
brew uninstall --cask virtual-hid-driver
```

The cask's uninstall directives stop its daemon, request deactivation and remove package files. Do not remove it while another app depends on the driver. The cask conflicts with Homebrew's full `karabiner-elements` package.

## Usage

```sh
macos-input --version
macos-input --dry-run key cmd+h
macos-input key cmd+h ctrl+shift+a enter
macos-input move relative 100 -50
macos-input move absolute 500 300
macos-input move percent 50 50 --smooth 0.5
macos-input --stdin
```

Keys: one lowercase letter, digit or named key, plus optional `cmd`, `ctrl`, `shift`, `alt`/`option`. Named keys: `enter`, `escape`, `backspace`, `tab`, `space`, `minus`, `equal`, `left-bracket`, `right-bracket`, `backslash`, `semicolon`, `quote`, `grave`, `comma`, `period`, `slash`, `delete`, `left`, `right`, `up`, `down`. Each chord presses then releases.

Mouse modes:

- `relative X Y`: signed integer HID counts, split into the driver's -127..127 report range. Mouse acceleration affects screen distance.
- `absolute X Y`: global macOS screen points, top-left origin, including negative coordinates on secondary displays. Targets must lie on an active display.
- `percent X Y`: 0-100 on the display containing the cursor when the command starts. 0/100 map to the first/last screen point, not outside the edge.
- Movement has no animation by default. `--smooth SECONDS` adds ease-in/out interpolation; zero remains unanimated. Absolute modes use cursor feedback to compensate for acceleration, accept at most 0.5-point error per axis, and fail after five seconds of correction beyond the requested duration. Some coordinates may be unreachable because of acceleration or display boundaries.

All emitted movement uses the driver. CoreGraphics only reads cursor/display geometry; there is no cursor-warp or Quartz-event injection fallback. Smoothing is best effort, not a real-time timing guarantee.

`--stdin` keeps virtual devices alive until EOF/Ctrl+C, prints `ready`, and accepts one command per line (for example `key cmd+h` or `move percent 50 50`). It prints `ok` after each chord's press/release responses or completed move; this does not prove a foreground app handled the input. `--dry-run` validates syntax without root, driver, screen reads or input. Errors go to stderr and exit nonzero; Ctrl+C exits 130.

### Running without sudo

Live input needs access to the driver daemon's socket, which is root-only by default. Run commands with `sudo`, or join the `virtual-hid` group once and open a new terminal:

```sh
sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
```

The cask creates the group empty and adds two ACL entries to `/Library/Application Support/org.pqrs/tmp/rootonly`: `search` on the folder, and inherited `write` for files created in it. The daemon recreates its socket there on every start, and the new socket inherits group write access. Members can drive the virtual keyboard and mouse, so add only accounts you trust with input control. The folder holds only this driver's socket; if another app ever puts its own sockets there, the group gets write access to them as well.

To leave the group: `sudo dseditgroup -o edit -d "$USER" -t user virtual-hid`. Uninstalling the cask removes the ACL entries but keeps the group, because cask upgrades reinstall and would otherwise drop its members. To delete it: `sudo dseditgroup -o delete virtual-hid`.

## Driver and permissions

Live operation needs the separately installed/approved [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) driver and its running root daemon. The cask installs the package and owns the root daemon. Approval remains manual. Root, or the `virtual-hid` group, is required by that daemon's socket permissions, not by our build or app-launch code. No developer-certificate signing or launchd registration is required for this foreground client. Driver signing and system-extension approval remain separate requirements.

Input affects whichever app is focused. Caller-side app checks are not an atomic focus lock. Idle-timer resets, auto-lock prevention and real pointer precision remain unverified until authorized testing with the driver.

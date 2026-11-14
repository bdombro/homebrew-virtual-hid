# Changelog

All notable changes are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Renamed the GitHub repository to `homebrew-virtual-hid`; the tap is
  `bdombro/virtual-hid`.
- The `macos-input` formula is CLI-only, with no Homebrew service; its caveats
  show driver setup only while the driver is missing.
- New `virtual-hid-driver` cask installs the driver package, requests
  activation, and installs its own root LaunchDaemon.
- Live commands exit non-zero with setup text when the driver is missing.
- New just recipes: `install-local`, `install-github`, `uninstall`, `status`,
  `driver-start`, `driver-stop` and `driver-restart`.
- Installs no longer run tests automatically.

### Fixed

- Live input no longer times out after the first report ("Timed out waiting
  for the driver daemon"), which left a key held down.
- The virtual keyboard reports a US country code so macOS can identify it.
- Migration: run `brew uninstall macos-input`, `brew trust bdombro/macos-input`
  (newer Homebrew refuses to touch casks from untrusted taps),
  `brew uninstall --cask karabiner-driverkit-virtualhiddevice`, then
  `brew untap bdombro/macos-input`, then the new install commands from the README.

### Removed

- Embedded `driver-install` command, shell templates, build generation and
  installer-only tests. Use the `virtual-hid-driver` cask instead.
- `scripts/dev-formula.ts` and the `install`/`reinstall` aliases,
  `reinstall-local` and `install-production` recipes.

## [0.0.2] - 2026-11-13

### Added

- Guided `driver-install` with confirmation, pinned package verification,
  launchd setup, and explicit manual approval instructions.
- Shared manual driver setup instructions in Homebrew caveats and CLI help.
- Pinned Homebrew driver cask, including package removal and driver deactivation.

### Changed

- `driver-install` delegates package download, checksum verification and installation
  to Homebrew instead of implementing its own installer.

### Fixed

- Refresh the production tap before installing newly published release formulae.

## [0.0.1] - 2026-11-13

### Added

- Virtual-HID keyboard chords and persistent stdin sessions.
- Relative, absolute, and display-percentage mouse movement with optional smoothing.
- Homebrew local installation and public GitHub release tooling.
- Explicit macOS 13.0 deployment target without newer floating-point parsing APIs.

### Fixed

- Release checks run only the C++ suites, without TypeScript type-checking or Bun tests.

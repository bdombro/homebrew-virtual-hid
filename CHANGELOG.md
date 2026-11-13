# Changelog

All notable changes are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

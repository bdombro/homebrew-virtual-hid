# Homebrew distribution

Adapted from argsbarg's Homebrew example: one repository owns `Formula/`, `Casks/`,
local development installs, and GitHub release assets. The application remains
C++/CMake; Bun runs maintainer scripts directly, without TypeScript
type-checking or Bun tests.

## Local development

The root justfile covers the tap: installs, the driver daemon, group access
and releases. Its `build`, `test`, `release` and `setup` recipes delegate to
`clients/macos-input/justfile`, which owns the CLI's build, tests and Bun
release tooling (`clients/macos-input/scripts/`).

```sh
just setup
just test
just install-local
just install-github
just status
just sudo-group-add
just uninstall
```

`install-local` links this checkout as the `bdombro/virtual-hid` tap and
installs its cask and formula, but the formula downloads the latest released
CLI binary, not a local build. `install-github` taps GitHub main exactly as users do.
Both first run `uninstall`, which removes `macos-input`, the
`virtual-hid-driver` cask and the tap directory
`$(brew --repository)/Library/Taps/bdombro/homebrew-virtual-hid` (a symlink for
`install-local`, a clone for `install-github`).

`status` shows driver activation state and whether the root daemon is loaded.
`driver-start` enables and bootstraps the
`com.github.bdombro.virtual-hid-driver.daemon` LaunchDaemon, `driver-stop`
disables and boots it out, and `driver-restart` kickstarts it. `status` and the
`driver-*` recipes run `sudo launchctl` and prompt for a password.
`sudo-group-add` and `sudo-group-remove` add or remove the current user from
the `virtual-hid` group and flush the membership cache; open a new terminal
afterward. `uninstall` keeps the group.

Installs never run tests; run `just test` or
`brew test bdombro/virtual-hid/macos-input` explicitly. Never run builds or
`brew install` with sudo.

## Public installation

```sh
brew tap bdombro/virtual-hid
brew trust bdombro/virtual-hid
brew install --cask virtual-hid-driver
brew install macos-input
brew upgrade macos-input
```

The formula is CLI-only. Its caveats print `clients/macos-input/resources/driver-setup.txt` only
while the Manager app is missing; otherwise they print a reminder that live
input needs sudo or membership in the `virtual-hid` group.

The `virtual-hid-driver` cask installs upstream v8.8.0's signed and notarized
package, requests activation, and installs and starts its own root
LaunchDaemon `com.github.bdombro.virtual-hid-driver.daemon` (not a Homebrew service).
Approval stays manual; see
[driver](driver.md). The cask's
uninstall unloads that daemon, requests deactivation, removes the package files
and deletes the plist. It conflicts with the `karabiner-elements` cask. Do not
run `brew install --cask` with sudo.

Formulae use ordinary public GitHub downloads without a custom authenticated
strategy. Archives contain only the executable. Architecture and minimum
macOS requirements come from the compiled Mach-O binary; a native arm64 build
is not advertised as Intel-compatible. Homebrew does not provide Bun or build
dependencies to end users. Shell completions are not generated because this
CLI does not implement the example's `completion` command.

CMake defaults to a macOS 13.0 deployment target, matching the reviewed
driver's supported OS range instead of inheriting the build machine's SDK
version. Building still needs a recent C++26 compiler. Older-OS runtime
testing has not been performed.

## Updating the driver

```sh
just driver-update
```

Pins the cask to upstream's latest release (version and package SHA-256) and
`clients/macos-input/CMakeLists.txt` to that release's commit, so the CLI
speaks the same protocol as the daemon. It lists docs that still mention the
old version. Review upstream's changes and run `just test`, then release
`macos-input` so its binary matches the new driver.

## Releases and changelog

`clients/macos-input/VERSION` starts at `0.0.0`; the first minor release is `0.1.0`. CMake embeds
it in `macos-input --version`. Write user-facing changes under
`## [Unreleased]` in `clients/macos-input/CHANGELOG.md`.

Once the independent app repository has an initial commit and an `origin`
pointing to the public `bdombro/homebrew-virtual-hid` repository:

```sh
just release minor --dry-run
just release minor
```

The dry-run is offline and changes nothing. A real release runs without a
confirmation prompt: it checks the repository and tag, and runs the C++ tests. It
bumps `VERSION`, promotes Unreleased to a dated changelog section, builds the
binary, creates `clients/macos-input/dist/macos-input.zip`, and writes the release formula with its
SHA-256. It stages every working-tree change (`git add -A`) into the release
commit, then tags, atomically pushes the branch and tag, and publishes the zip
using the changelog as notes.

Requires authenticated `gh`, push access to `origin`, and an existing GitHub
repository. This tooling does not create that repository. The checked-in release
formula retains its published asset URL/hash when caveats
change; new CLI code reaches public installations only with a new binary release.
Old releases are retained.

Failures stop immediately and leave completed work visible rather than
silently rolling back or retrying publication. Inspect local Git and GitHub
state before recovery, particularly if pushing or uploading failed.

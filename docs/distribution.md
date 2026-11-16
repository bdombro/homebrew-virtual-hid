# Homebrew distribution

One repository owns `Formula/`, `Casks/`, `VERSION`, `CHANGELOG.md`, CI release
workflows, and `clients/macos-input/`.

## Local development

The root justfile covers the tap: installs, the driver daemon, group access
and releases. Its `build`, `clean`, `doctor`, `fmt`, `lint`, `test` and
`upgrade-deps` recipes delegate to `clients/macos-input/justfile`.

```sh
just doctor
just test
just build
just install
just status
just sudo-group-add
just uninstall
```

`just install` runs `just uninstall`, taps `bdombro/virtual-hid` by explicit
URL (`https://github.com/bdombro/homebrew-virtual-hid`), and installs the
released cask and formula from GitHub exactly as users do. `just uninstall`
removes `macos-input`, the `virtual-hid-driver` cask and untaps
`bdombro/virtual-hid`.

`just test` builds Debug with ASan + UBSan and runs the tests (pass an optional
doctest filter to run matching cases). `just build` compiles Release and stages
`build/bin/macos-input`. `just fmt` and `just lint` use `LLVM_BIN` (defaults to
`$(brew --prefix llvm@23)/bin`).

`status` shows driver activation state and whether the root daemon is loaded.
`driver-start` enables and bootstraps the
`com.github.bdombro.virtual-hid-driver.daemon` LaunchDaemon, `driver-stop`
disables and boots it out, and `driver-restart` kickstarts it. `status` and the
`driver-*` recipes run `sudo launchctl` and prompt for a password.
`sudo-group-add` and `sudo-group-remove` add or remove the current user from
the `virtual-hid` group and flush the membership cache. `uninstall` keeps the group.

Installs never run tests; run `just test` or
`brew test bdombro/virtual-hid/macos-input` explicitly. Never run builds or
`brew install` with sudo.

## Public installation

```sh
brew tap bdombro/virtual-hid https://github.com/bdombro/homebrew-virtual-hid
brew install --cask bdombro/virtual-hid/virtual-hid-driver
brew install bdombro/virtual-hid/macos-input
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
`clients/macos-input/CMakeLists.txt` to that release's commit, and lists docs
that still mention the old version.

## Releases and changelog

`VERSION` at the repository root embeds into `macos-input --version`. Write
changes under `## Unreleased` in `CHANGELOG.md` (`Internal: ...` for internal
changes).

Releases run via GitHub Actions:

```sh
just release <major|minor|patch>
```

`just release` triggers `.github/workflows/release.yml`, watches the run, and
pulls the release commit. The workflow runs `test.yml`, bumps `VERSION`,
promotes `## Unreleased` in `CHANGELOG.md`, builds the macOS Release binary,
packages `macos-input-arm64-macos.tar.gz`, updates `Formula/macos-input.rb`,
commits, tags, pushes, and creates the GitHub release.

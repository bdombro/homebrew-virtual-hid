# Homebrew distribution

Adapted from argsbarg's Homebrew example: one repository owns `Formula/`, `Casks/`,
local development installs, and GitHub release assets. The application remains
C++/CMake; Bun runs maintainer scripts directly, without TypeScript
type-checking or Bun tests.

## Local development

```sh
just setup
just test
just install-local
just reinstall-local
just uninstall
```

`install` and `reinstall` alias their local variants. `install-local` builds
`dist/macos-input`, packages it as a zip, and links this checkout as the
`bdombro/macos-input` tap. It temporarily writes a `file://` formula, installs
or reinstalls the keg, runs its no-input tests, and restores the original
formula even if Homebrew fails. It refuses to overwrite an existing tap.
After a killed process, use `bun scripts/dev-formula.ts reset` if a backup remains.

`reinstall-local` replaces the installed executable for quick development.
`uninstall` removes the keg but leaves the tap; untap separately if desired.
`install-production` switches our local tap symlink to the public GitHub tap
and fast-forwards that tap before installing/reinstalling its release formula.

No recipe installs Karabiner, grants permissions, starts a daemon, or emits
keyboard/mouse input. Do not run builds or Homebrew with sudo.

## Public installation

After the first release has been published:

```sh
brew tap bdombro/macos-input https://github.com/bdombro/macos-input.git
brew install bdombro/macos-input/macos-input
brew upgrade bdombro/macos-input/macos-input
```

Homebrew caveats print the manual download, verification, installation and
activation instructions from `resources/driver-setup.txt`, also embedded in the
executable. For guided setup, run as your normal user:

```sh
macos-input driver-install --dry-run
macos-input driver-install
```

This command, after interactive confirmation, delegates package installation to
`brew install --cask bdombro/macos-input/karabiner-driverkit-virtualhiddevice`,
then configures its persistent root daemon using sudo. Homebrew handles the
pinned download, checksum verification and privileged package installer.
Installing the CLI formula alone never installs the cask.
GUI activation/approval and any requested restart remain manual.
See [driver setup](../README.md#driver-setup-required-for-live-input).
The formula's no-input tests also exercise the setup preview.

The checked-in cask uses upstream v8.8.0's signed/notarized package directly.
It is available through the same local tap link, without formula staging.
Its uninstall unloads the driver services, requests GUI-user deactivation,
and removes package-receipt files. It conflicts with the full `karabiner-elements`
cask because they share driver files. Do not run `brew install --cask` with sudo.
On Homebrew versions requiring explicit trust, trust only the named cask with
`brew trust --cask bdombro/macos-input/karabiner-driverkit-virtualhiddevice`.

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

## Releases and changelog

`VERSION` starts at `0.0.0`; the first minor release is `0.1.0`. CMake embeds
it in `macos-input --version`. Write user-facing changes under
`## [Unreleased]` in `CHANGELOG.md`.

Once the independent app repository has an initial commit and an `origin`
pointing to the public `bdombro/macos-input` repository:

```sh
just release minor --dry-run
just release minor
# Automation: just release patch --yes
```

The dry-run is offline and changes nothing. A real release asks for confirmation
(or requires `--yes` outside a terminal), requires a clean app working tree,
checks the repository and tag, and runs the C++ tests. It bumps `VERSION`, promotes
Unreleased to a dated changelog section, builds the binary, creates
`dist/macos-input.zip`, and writes the release formula with its SHA-256.
It commits only the version, changelog, and formula, then tags, atomically
pushes the branch and tag, and publishes the zip using the changelog as notes.

Requires authenticated `gh`, push access to `origin`, and an existing GitHub
repository. This tooling does not create that repository. `Formula/` has no
production formula until the first release; no placeholder URL/hash is shipped.
Old releases are retained.

Failures stop immediately and leave completed work visible rather than
silently rolling back or retrying publication. Inspect local Git and GitHub
state before recovery, particularly if pushing or uploading failed.

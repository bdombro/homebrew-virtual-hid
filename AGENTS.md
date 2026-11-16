# virtual-hid

Two-level Homebrew tap and C++26 CLI repository (`bdombro/homebrew-virtual-hid`).

## Layout

- Root owns `Formula/macos-input.rb`, `Casks/virtual-hid-driver.rb`, `VERSION`, `CHANGELOG.md`, `.github/`, `scripts/{release,formula-shared,driver-update}.*`, and `justfile` (`driver-*`, `sudo-group-*`, `status`, `install`, `uninstall`, `release`, plus delegated C++ recipes).
- `clients/macos-input/` owns the C++26/ObjC CLI source, tests, `CMakeLists.txt`, `vcpkg*.json`, and `homebrew-formula` tooling; see [clients/macos-input/AGENTS.md](clients/macos-input/AGENTS.md) for C++ rules and template alignment.

## Rules

- Keep `driver-*`, `sudo-group-*`, and `status` recipes intact.
- Never run `sudo`, `launchctl`, `brew install`/`tap`, or live non-`--dry-run` `key`/`move` commands during automated tests.

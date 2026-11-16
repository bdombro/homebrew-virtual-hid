set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set positional-arguments

platforms := "macos"
daemon := "com.github.bdombro.virtual-hid-driver.daemon"

_:
    @just --list

# Compile the Release binary and stage it into build/bin
build:
    just -f clients/macos-input/justfile build
    mkdir -p build/bin
    install -m 755 clients/macos-input/build/bin/macos-input build/bin/macos-input

# Remove build output
clean:
    just -f clients/macos-input/justfile clean
    rm -rf build

# Check required tools, C++26 support and env vars, printing fixes
doctor:
    just -f clients/macos-input/justfile doctor

# Restart the driver daemon
driver-restart:
    sudo launchctl kickstart -k system/{{ daemon }}

# Enable and start the driver daemon (persists across reboots)
driver-start:
    sudo launchctl enable system/{{ daemon }}
    sudo launchctl bootstrap system /Library/LaunchDaemons/{{ daemon }}.plist

# Stop and disable the driver daemon so it stays off after reboot
driver-stop:
    sudo launchctl disable system/{{ daemon }}
    sudo launchctl bootout system/{{ daemon }}

# Pin the driver cask and macos-input's client headers to upstream's latest release
driver-update:
    scripts/driver-update.sh

# Format C++ sources and justfiles
fmt:
    just -f clients/macos-input/justfile fmt
    just --fmt --unstable

# Clean-install the driver and macos-input from GitHub exactly as users do
install: uninstall
    brew tap bdombro/virtual-hid https://github.com/bdombro/homebrew-virtual-hid
    brew install --cask bdombro/virtual-hid/virtual-hid-driver
    brew install bdombro/virtual-hid/macos-input

# Check formatting, then lint with clang-tidy
lint:
    just -f clients/macos-input/justfile lint
    just --fmt --check --unstable

# Release on GitHub (tests per platform, version bump, changelog, build, formula, tag), then pull the release commit
release bump:
    gh workflow run release.yml -f bump="$1"
    sleep 5; id="$(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')"; if [ -t 1 ]; then gh run watch --compact --exit-status "$id"; else gh run watch --exit-status "$id" >/dev/null; fi || { gh run view "$id" --log-failed | tail -n 100; exit 1; }
    git pull --ff-only

# Show driver activation state and whether the root daemon is loaded
status:
    systemextensionsctl list | grep -i karabiner || echo "driver not activated: run the Manager activate command (no sudo), then approve in System Settings"
    sudo launchctl print system/{{ daemon }} | head -5

# Let the current user run live input without sudo
sudo-group-add:
    sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
    sudo dsmemberutil flushcache

# Require sudo again for the current user's live input
sudo-group-remove:
    sudo dseditgroup -o edit -d "$USER" -t user virtual-hid
    sudo dsmemberutil flushcache

# Debug build with ASan + UBSan, then run all tests, or only doctest cases matching filter
test filter="":
    just -f clients/macos-input/justfile test "$@"

# Remove macos-input, the driver (and its daemon), and the tap; the virtual-hid group stays
uninstall:
    brew uninstall macos-input || true
    brew uninstall --cask virtual-hid-driver || true
    brew untap bdombro/virtual-hid || true

# Move vcpkg registry baselines to latest, then run tests (no commit)
upgrade-deps:
    just -f clients/macos-input/justfile upgrade-deps

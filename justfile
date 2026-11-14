set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

tap_dir := `brew --repository` + "/Library/Taps/bdombro/homebrew-virtual-hid"
daemon := "com.github.bdombro.virtual-hid-driver.daemon"

_:
    @just --list

# Build and stage clients/macos-input/dist/macos-input
build:
    just clients/macos-input/build

# Restart the driver daemon
driver-restart:
    sudo launchctl kickstart -k system/{{daemon}}

# Enable and start the driver daemon (persists across reboots)
driver-start:
    sudo launchctl enable system/{{daemon}}
    sudo launchctl bootstrap system /Library/LaunchDaemons/{{daemon}}.plist

# Stop and disable the driver daemon so it stays off after reboot
driver-stop:
    sudo launchctl disable system/{{daemon}}
    sudo launchctl bootout system/{{daemon}}

# Clean-install the driver and macos-input exactly as users do, from GitHub main
install-github: uninstall
    brew tap bdombro/virtual-hid
    brew trust bdombro/virtual-hid
    brew install --cask virtual-hid-driver
    brew install macos-input

# Clean-install the driver and macos-input from this checkout's cask/formula (CLI binary is the latest release)
install-local: uninstall
    mkdir -p "$(dirname "{{tap_dir}}")"
    ln -s "{{justfile_directory()}}" "{{tap_dir}}"
    brew trust bdombro/virtual-hid
    brew install --cask virtual-hid-driver
    brew install macos-input

# Release macos-input (see docs/distribution.md)
release *ARGS:
    just clients/macos-input/release {{ARGS}}

# Install the release tooling's Bun dependencies
setup:
    just clients/macos-input/setup

# Show driver activation state and whether the root daemon is loaded
status:
    systemextensionsctl list | grep -i karabiner || echo "driver not activated: run the Manager activate command (no sudo), then approve in System Settings"
    sudo launchctl print system/{{daemon}} | head -5

# Let the current user run live input without sudo (open a new terminal afterward)
sudo-group-add:
    sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
    sudo dsmemberutil flushcache

# Require sudo again for the current user's live input
sudo-group-remove:
    sudo dseditgroup -o edit -d "$USER" -t user virtual-hid
    sudo dsmemberutil flushcache

# Run macos-input's Debug and Release tests
test:
    just clients/macos-input/test

# Remove macos-input, the driver (and its daemon), and the tap; the virtual-hid group stays
uninstall:
    brew uninstall macos-input || true
    brew uninstall --cask virtual-hid-driver || true
    rm -rf "{{tap_dir}}"

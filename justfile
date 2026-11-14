set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

_:
    @just --list

setup:
    bun install

configure configuration="Debug":
    CXX="${CXX:-/usr/bin/clang++}" cmake -S . -B build/cmake/{{configuration}} -G Ninja \
        -DCMAKE_BUILD_TYPE={{configuration}} \
        -DENABLE_SANITIZERS={{if configuration == "Debug" { "ON" } else { "OFF" }}}

test-debug: (configure "Debug")
    cmake --build build/cmake/Debug --parallel 2
    ctest --test-dir build/cmake/Debug --output-on-failure --no-tests=error

test-release: (configure "Release")
    cmake --build build/cmake/Release --parallel 2
    ctest --test-dir build/cmake/Release --output-on-failure --no-tests=error

build: (configure "Release")
    cmake --build build/cmake/Release --target macos-input --parallel 2
    mkdir -p dist
    install -m 755 build/cmake/Release/macos-input dist/macos-input

test: test-debug test-release

tap_dir := `brew --repository` + "/Library/Taps/bdombro/homebrew-virtual-hid"
daemon := "com.github.bdombro.virtual-hid-driver.daemon"

# Clean-install the driver and macos-input from this checkout's cask/formula (CLI binary is the latest release)
install-local: uninstall
    mkdir -p "$(dirname "{{tap_dir}}")"
    ln -s "{{justfile_directory()}}" "{{tap_dir}}"
    brew trust bdombro/virtual-hid
    brew install --cask virtual-hid-driver
    brew install macos-input

# Clean-install the driver and macos-input exactly as users do, from GitHub main
install-github: uninstall
    brew tap bdombro/virtual-hid
    brew trust bdombro/virtual-hid
    brew install --cask virtual-hid-driver
    brew install macos-input

# Remove macos-input, the driver (and its daemon), and the tap
uninstall:
    brew uninstall macos-input || true
    brew uninstall --cask virtual-hid-driver || true
    rm -rf "{{tap_dir}}"

# Show driver activation state and whether the root daemon is loaded
status:
    systemextensionsctl list | grep -i karabiner || echo "driver not activated: run the Manager activate command (no sudo), then approve in System Settings"
    sudo launchctl print system/{{daemon}} | head -5

# Enable and start the driver daemon (persists across reboots)
driver-start:
    sudo launchctl enable system/{{daemon}}
    sudo launchctl bootstrap system /Library/LaunchDaemons/{{daemon}}.plist

# Stop and disable the driver daemon so it stays off after reboot
driver-stop:
    sudo launchctl disable system/{{daemon}}
    sudo launchctl bootout system/{{daemon}}

# Restart the driver daemon
driver-restart:
    sudo launchctl kickstart -k system/{{daemon}}

release *ARGS:
    bun scripts/release.ts {{ARGS}}

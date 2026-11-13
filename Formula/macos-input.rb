class MacosInput < Formula
  desc "Send keyboard and mouse input through Karabiner's virtual HID driver"
  homepage "https://github.com/bdombro/macos-input"
  url "https://github.com/bdombro/macos-input/releases/download/v0.0.2/macos-input.zip"
  version "0.0.2"
  sha256 "5f8b9885ae13ffb58ccb56d9452a1c6e61c22441df9bd46b464c107617df605c"

  class MinimumMacOSRequirement < Requirement
    fatal true
    satisfy(build_env: false) { OS.mac? && MacOS.full_version >= MacOSVersion.new("13.0") }

    def message
      "macos-input requires macOS 13.0 or newer."
    end
  end

  depends_on :macos
  depends_on MinimumMacOSRequirement
  depends_on arch: :arm64

  def install
    bin.install "macos-input"
  end

  def caveats
    <<~'EOS'
      macos-input depends on Karabiner-DriverKit-VirtualHIDDevice v8.8.0,
      an open-source, Developer ID-signed and Apple-notarized virtual-HID driver.
      Signing/notarization is not a guarantee that software is harmless.
      
      Source code: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice
      Release: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v8.8.0
      
      Homebrew package installation (administrator authentication required):
        brew install --cask bdombro/macos-input/karabiner-driverkit-virtualhiddevice
      The cask downloads/verifies v8.8.0 and runs macOS Installer. Activation,
      approval, and a running daemon are still required; see below.
      If Homebrew requires trust, follow its instructions to trust only this cask.
      
      Manual download and installation:
        1. Download Karabiner-DriverKit-VirtualHIDDevice-8.8.0.pkg from that release.
           Verify its SHA-256 with:
             shasum -a 256 Karabiner-DriverKit-VirtualHIDDevice-8.8.0.pkg
           Expected:
             2b6e323bf690fde05b24ca2648536916a274d01496e3826dc8b050b63f8b9842
        2. Open the package and follow Installer's administrator prompts.
        3. Request activation as your normal GUI user:
             /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
        4. Follow macOS's approval prompts. On recent macOS versions, check
           System Settings > General > Login Items & Extensions > Driver Extensions.
           On older versions, check Privacy & Security. Restart if macOS requests it.
        5. For manual, foreground operation, leave this running in another terminal:
             sudo "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
      
      Or let macos-input install the Homebrew cask when needed and configure a
      persistent root daemon for you:
        macos-input driver-install
      
      The guided command explains its actions and asks before requesting sudo.
      Driver activation/approval remains a manual step. Installing the CLI formula
      alone does not install the driver or start its daemon. Live input requires sudo.
    EOS
  end

  test do
    assert_match "macos-input #{version}", shell_output("#{bin}/macos-input --version")
    assert_equal "validated cmd+h\n", shell_output("#{bin}/macos-input --dry-run key cmd+h")
    assert_equal "validated move\n", shell_output("#{bin}/macos-input --dry-run move percent 50 50")
    assert_match "Source code:", shell_output("#{bin}/macos-input driver-install --dry-run")
  end
end

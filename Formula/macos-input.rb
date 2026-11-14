class MacosInput < Formula
  desc "Send keyboard and mouse input through Karabiner's virtual HID driver"
  homepage "https://github.com/bdombro/homebrew-virtual-hid"
  url "https://github.com/bdombro/homebrew-virtual-hid/releases/download/v0.1.2/macos-input.zip"
  version "0.1.2"
  sha256 "2b3f7159fc1a502026c0486b7dbfceafeb80fca618bb36d3c1fda7d9f92ca2f4"

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
    if File.exist?("/Applications/.Karabiner-VirtualHIDDevice-Manager.app")
      return <<~EOS
        Live input needs sudo, or membership in the virtual-hid group. To join it,
        run this once, then open a new terminal:
          sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
      EOS
    end

    <<~'EOS'
      Live input requires Karabiner-DriverKit-VirtualHIDDevice v8.8.0,
      an open-source, Developer ID-signed and Apple-notarized driver.
      Installing the CLI alone does not install or activate this driver.

      Source code: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice
      Release: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v8.8.0

      Complete these steps in order as your normal user. Skip steps already done.

      1. Tap and trust the repository, then install the driver cask
         (Homebrew will request administrator authentication):
           brew tap bdombro/virtual-hid
           brew trust bdombro/virtual-hid
           brew install --cask virtual-hid-driver

         The cask installs the driver, requests activation and starts its daemon.

      2. Approve the driver when macOS prompts. If you clicked OK or the popup
         disappeared, open System Settings > General > Login Items & Extensions,
         click "By Category", click the (i) next to "Driver Extensions", and turn on
         .Karabiner-VirtualHIDDevice-Manager.app (org.pqrs.Karabiner-DriverKit-VirtualHIDDevice).
         On older macOS versions, check Privacy & Security. Restart if requested.

         If no approval prompt appeared, request activation manually, WITHOUT sudo:
           /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate

      3. Check the daemon:
           sudo launchctl print system/com.github.bdombro.virtual-hid-driver.daemon

      Live input needs sudo, or membership in the virtual-hid group. To join it,
      run this once, then open a new terminal:
        sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
      Signing/notarization is not a guarantee that software is harmless.
    EOS
  end

  test do
    assert_match "macos-input #{version}", shell_output("#{bin}/macos-input --version")
    assert_equal "validated cmd+h\n", shell_output("#{bin}/macos-input --dry-run key cmd+h")
    assert_equal "validated move\n", shell_output("#{bin}/macos-input --dry-run move percent 50 50")
  end
end

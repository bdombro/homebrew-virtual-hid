class MacosInput < Formula
  desc "Send keyboard and mouse input through Karabiner's virtual HID driver"
  homepage "https://github.com/bdombro/macos-input"
  url "https://github.com/bdombro/macos-input/releases/download/v0.0.1/macos-input.zip"
  version "0.0.1"
  sha256 "afe2e353236b94eaa85c17db12b42234166f59d472379224e12531695c953a7a"

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
    <<~EOS
      Live input needs the separately approved Karabiner v8.8.0 driver and its root daemon.
      This formula does not install or activate the driver, or start a service.
      Build/install without sudo; only live input needs sudo.
    EOS
  end

  test do
    assert_match "macos-input #{version}", shell_output("#{bin}/macos-input --version")
    assert_equal "validated cmd+h\n", shell_output("#{bin}/macos-input --dry-run key cmd+h")
    assert_equal "validated move\n", shell_output("#{bin}/macos-input --dry-run move percent 50 50")
  end
end

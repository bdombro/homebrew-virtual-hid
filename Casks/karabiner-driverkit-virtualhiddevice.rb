cask "karabiner-driverkit-virtualhiddevice" do
  version "8.8.0"
  sha256 "2b6e323bf690fde05b24ca2648536916a274d01496e3826dc8b050b63f8b9842"

  url "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v#{version}/Karabiner-DriverKit-VirtualHIDDevice-#{version}.pkg"
  name "Karabiner-DriverKit-VirtualHIDDevice"
  desc "Virtual HID driver for macOS keyboard and mouse input"
  homepage "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice"

  conflicts_with cask: "karabiner-elements"
  depends_on macos: :ventura

  pkg "Karabiner-DriverKit-VirtualHIDDevice-#{version}.pkg"

  uninstall launchctl: [
              "com.bdombro.macos-input.driver",
              "org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon",
            ],
            script:    {
              executable: "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager",
              args:       ["deactivate"],
              sudo:       false,
            },
            pkgutil:   "^org\\.pqrs\\.Karabiner-DriverKit-VirtualHIDDevice$"

  caveats <<~EOS
    Run macos-input driver-install to configure the persistent root daemon.
    Activation/approval remains manual, as your normal GUI user:
      /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
    Follow macOS approval prompts/System Settings and restart if requested.
    Uninstalling this cask stops the driver services and requests deactivation.
    Do not uninstall it while another application depends on this driver.
  EOS
end

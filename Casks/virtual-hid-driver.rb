cask "virtual-hid-driver" do
  version "8.8.0"
  sha256 "2b6e323bf690fde05b24ca2648536916a274d01496e3826dc8b050b63f8b9842"

  url "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v#{version}/Karabiner-DriverKit-VirtualHIDDevice-#{version}.pkg"
  name "Karabiner-DriverKit-VirtualHIDDevice"
  desc "Virtual HID keyboard and mouse driver with its root daemon"
  homepage "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice"

  conflicts_with cask: "karabiner-elements"
  depends_on macos: :ventura

  pkg "Karabiner-DriverKit-VirtualHIDDevice-#{version}.pkg"

  daemon_label = "com.github.bdombro.virtual-hid-driver.daemon"
  daemon_plist = "/Library/LaunchDaemons/#{daemon_label}.plist"
  manager = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

  postflight_steps do
    # Unprivileged steps run in Homebrew's sandbox, where the activation request never reaches macOS.
    # A sudo step runs outside the sandbox; sudo -u drops back to the invoking user, as the request requires.
    run "/usr/bin/sudo",
        args:         [
          "-u", "{{user}}", "--",
          "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager",
          "activate"
        ],
        sudo:         true,
        must_succeed: false,
        print_stdout: true

    write_file "com.github.bdombro.virtual-hid-driver.daemon.plist", <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>com.github.bdombro.virtual-hid-driver.daemon</string>
        <key>ProgramArguments</key>
        <array>
          <string>/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
      </dict>
      </plist>
    XML

    # chdir defaults to staged_path, where write_file put the plist.
    run "/usr/bin/install",
        args:  ["-o", "root", "-g", "wheel", "-m", "644", "com.github.bdombro.virtual-hid-driver.daemon.plist",
                "/Library/LaunchDaemons/com.github.bdombro.virtual-hid-driver.daemon.plist"],
        chdir: ".",
        sudo:  true
    run "/bin/launchctl",
        args:         ["bootout", "system/com.github.bdombro.virtual-hid-driver.daemon"],
        sudo:         true,
        must_succeed: false,
        print_stderr: false
    run "/bin/launchctl",
        args:         ["enable", "system/com.github.bdombro.virtual-hid-driver.daemon"],
        sudo:         true,
        must_succeed: false
    run "/bin/launchctl",
        args: ["bootstrap", "system", "/Library/LaunchDaemons/com.github.bdombro.virtual-hid-driver.daemon.plist"],
        sudo: true
  end

  uninstall launchctl: daemon_label,
            script:    {
              executable: manager,
              args:       ["deactivate"],
              sudo:       false,
            },
            pkgutil:   "^org\\.pqrs\\.Karabiner-DriverKit-VirtualHIDDevice$",
            delete:    daemon_plist

  caveats <<~EOS
    Approve the driver when macOS prompts, or open System Settings:
      General > Login Items & Extensions > Driver Extensions
    Restart if requested.

    If no approval prompt appears, request activation as your normal user (no sudo):
      #{manager} activate

    Check the daemon:
      sudo launchctl print system/#{daemon_label}
  EOS
end

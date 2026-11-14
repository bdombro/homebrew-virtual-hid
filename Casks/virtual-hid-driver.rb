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
    # Sudo steps run in the unsandboxed parent, so print_stdout reliably reaches the terminal.
    run "/bin/echo",
        args:         [
          "A macOS popup will ask you to allow the Karabiner VirtualHIDDevice driver, " \
          "and the install waits until you approve it. If you clicked OK or the popup disappeared, " \
          "open System Settings > General > Login Items & Extensions, click \"By Category\", " \
          "click the (i) next to \"Driver Extensions\", and turn on " \
          ".Karabiner-VirtualHIDDevice-Manager.app (org.pqrs.Karabiner-DriverKit-VirtualHIDDevice).",
        ],
        sudo:         true,
        must_succeed: false,
        print_stdout: true
    run "/usr/bin/sudo",
        args:         ["-u", "{{user}}", "--", "/usr/bin/open",
                       "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"],
        sudo:         true,
        must_succeed: false

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

    # Register the virtual keyboard (product-vendor-country: 0x27db, 0x16c0, US) as ANSI so
    # macOS doesn't open Keyboard Setup Assistant each time a client attaches it.
    run "/usr/bin/defaults",
        args:         ["write", "/Library/Preferences/com.apple.keyboardtype", "keyboardtype",
                       "-dict-add", "10203-5824-33", "-int", "40"],
        sudo:         true,
        must_succeed: false

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

  uninstall early_script: {
              executable:   "/usr/libexec/PlistBuddy",
              args:         ["-c", "Delete :keyboardtype:10203-5824-33",
                             "/Library/Preferences/com.apple.keyboardtype.plist"],
              sudo:         true,
              must_succeed: false,
              print_stderr: false,
            },
            launchctl:    daemon_label,
            script:       {
              executable: manager,
              args:       ["deactivate"],
              sudo:       false,
            },
            pkgutil:      "^org\\.pqrs\\.Karabiner-DriverKit-VirtualHIDDevice$",
            delete:       daemon_plist

  caveats <<~EOS
    Approve the driver when macOS prompts. If you clicked OK or the popup disappeared,
    open System Settings > General > Login Items & Extensions, click "By Category",
    click the (i) next to "Driver Extensions", and turn on
    .Karabiner-VirtualHIDDevice-Manager.app (org.pqrs.Karabiner-DriverKit-VirtualHIDDevice).
    On older macOS versions, check Privacy & Security. Restart if requested.

    If no approval prompt appears, request activation as your normal user (no sudo):
      #{manager} activate

    Check the daemon:
      sudo launchctl print system/#{daemon_label}
  EOS
end

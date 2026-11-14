# Driver

`macos-input` sends input through the open-source [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) driver, pinned to [v8.8.0](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v8.8.0). It is Developer ID-signed and Apple-notarized; that is not a guarantee of harmlessness.

The `virtual-hid-driver` cask ([Casks/virtual-hid-driver.rb](../Casks/virtual-hid-driver.rb)) installs it. The `macos-input` formula is CLI-only and doesn't depend on the cask.

## What the cask does

`brew install --cask virtual-hid-driver` runs these steps. Homebrew asks for your password for the ones that need root.

1. **Downloads** upstream's signed `.pkg` from the driver's GitHub release and checks it against the cask's pinned `sha256`.
2. **Installs the pkg** with macOS Installer. It places the Manager app at `/Applications/.Karabiner-VirtualHIDDevice-Manager.app` and the daemon app under `/Library/Application Support/org.pqrs/`.
3. **Requests activation**: it opens System Settings and runs `Manager activate` as your normal user, which triggers the approval popup. The cask runs it through `sudo -u <you>` because, inside Homebrew's sandbox, the request never reaches macOS.
4. **Registers the virtual keyboard as ANSI** in `com.apple.keyboardtype`, so Keyboard Setup Assistant doesn't open each time a client attaches it.
5. **Installs a root LaunchDaemon**, `com.github.bdombro.virtual-hid-driver.daemon` (`RunAtLoad`, `KeepAlive`), in `/Library/LaunchDaemons`. Upstream ships the daemon program but leaves launching it to the installer. This isn't a Homebrew service.
6. **Sets up the `virtual-hid` group and its socket access** (see [Group access](#group-access)).
7. **Enables and bootstraps the daemon**, so it runs now and on every boot.

Uninstalling reverses this:

- removes the ACL entries and the keyboard-type entry;
- stops the daemon and requests deactivation;
- removes the package files and the plist.

The `virtual-hid` group is kept, because cask upgrades uninstall and reinstall, which would otherwise drop its members.

The cask conflicts with Homebrew's `karabiner-elements` cask. Don't remove it while another app depends on the driver. Never run `brew install --cask` with sudo.

## Approval

Approve the driver when macOS prompts. If you clicked OK or the popup disappeared:

1. Open System Settings > General > Login Items & Extensions.
2. Click "By Category", then click ⓘ next to "Driver Extensions".
3. Turn on `.Karabiner-VirtualHIDDevice-Manager.app` (`org.pqrs.Karabiner-DriverKit-VirtualHIDDevice`).

On older macOS versions, check Privacy & Security instead. Restart if asked.

If no prompt appeared, request activation as your logged-in user, without sudo:

```sh
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
```

## Group access

Live input talks to the daemon's socket, `/Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock`, which is root-only by default. Run `macos-input` with sudo, or join the `virtual-hid` group once:

```sh
sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
sudo dsmemberutil flushcache
```

The cask creates the group empty and adds two ACL entries to the `rootonly` folder:

- `search` on the folder itself;
- inherited `write` for files created in it.

The daemon recreates its socket on every start, and the new socket inherits group write access. The daemon resets the folder's mode to 0700 but leaves ACLs alone. Connecting needs only write access, not read.

Members can drive the virtual keyboard and mouse, so add only accounts you trust with input control. The folder holds only this driver's socket. If another app ever puts its own sockets there, the group would get write access to them too.

To leave the group:

```sh
sudo dseditgroup -o edit -d "$USER" -t user virtual-hid
sudo dsmemberutil flushcache
```

macOS caches group membership, so a stale answer can deny access after joining (or allow it after leaving) until `sudo dsmemberutil flushcache` runs.

To delete the group:

```sh
sudo dseditgroup -o delete virtual-hid
```

## Troubleshooting

If live input reports a missing socket, check the daemon:

```sh
sudo launchctl print system/com.github.bdombro.virtual-hid-driver.daemon
systemextensionsctl list | grep -i karabiner
```

From a checkout, `just status` runs both checks. `just driver-start`, `just driver-stop` and `just driver-restart` control the daemon.

The formula's caveats print the [setup guide](../clients/macos-input/resources/driver-setup.txt) while the driver is missing. Live commands without the driver exit nonzero and print the same guide. They never install, start or prompt for anything.

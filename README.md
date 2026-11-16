# virtual-hid

Press keys and move the mouse on macOS from the command line or a script. Like [ydotool](https://github.com/ReimuNotMoe/ydotool) for Linux.

This repo hosts:

1. Homebrew tap: virtual-hid
2. A recipe for [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice), the popular OSS virtual-hid driver on macOS
3. A recipe and source code for `macos-input`, a small CLI to drive the virtual keyboard and mouse


## Why this exists

Makes it easy to send REAL keyboard and mouse input on macOS. Other solutions (Quartz) only simulate input at a higher level, which does not behave exactly like a real keyboard and mouse.

That, and having a simple CLI to drive it, makes automating fun.

## Install

```sh
brew tap bdombro/virtual-hid https://github.com/bdombro/homebrew-virtual-hid
brew install --cask bdombro/virtual-hid/virtual-hid-driver
brew install bdombro/virtual-hid/macos-input
```

1. **Approve the driver** when macOS prompts. Missed it? Open System Settings > General > Login Items & Extensions > By Category > ⓘ next to Driver Extensions, and turn on `.Karabiner-VirtualHIDDevice-Manager.app`.
2. **Skip sudo** by joining the `virtual-hid` group:

   ```sh
   sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
   sudo dsmemberutil flushcache
   ```

## Usage

Input goes to whichever app is focused.

> Note: `sudo ` is required unless you have joined the `virtual-hid` group as described above.

### Keyboard

```sh
macos-input key cmd+h                 # hide the front app
macos-input key cmd+space             # open Spotlight
macos-input key ctrl+shift+a enter    # several chords in a row
```

A chord is one key plus optional `cmd`, `ctrl`, `shift`, `alt`/`option`. Keys are lowercase letters, digits, arrows and names like `enter`, `escape`, `tab`, `space`; see the [full list](clients/macos-input/README.md#keys).

### Mouse

```sh
macos-input move percent 50 50                # center of the current display
macos-input move absolute 500 300             # screen points from the top-left
macos-input move relative 100 -50             # nudge right and up
macos-input move percent 90 10 --smooth 0.5   # glide there over half a second
```

### Scripts

`--stdin` keeps the devices alive and runs one command per line, printing `ok` after each:

```sh
printf 'key cmd+space\nmove percent 50 50\n' | macos-input --stdin
```

Add `--dry-run` to any command to check its syntax without sending input.

## Docs

- [macos-input](clients/macos-input/README.md): full CLI reference, behavior details and building from source
- [Driver](docs/driver.md): what the cask installs, approval, the `virtual-hid` group, troubleshooting
- [Distribution](docs/distribution.md): local installs, just recipes and releases

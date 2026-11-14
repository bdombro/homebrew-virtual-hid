# virtual-hid

Press keys and move the mouse on macOS from the command line or a script. Like [ydotool](https://github.com/ReimuNotMoe/ydotool) for Linux.

virtual-hid pairs a signed, Apple-notarized virtual keyboard and mouse driver ([Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)) with `macos-input`, a small CLI that drives it. macOS sees a real HID device, so input takes the same path as a physical keyboard and mouse.

## Install

```sh
brew tap bdombro/virtual-hid
brew trust bdombro/virtual-hid
brew install --cask virtual-hid-driver
brew install macos-input
```

1. **Approve the driver** when macOS prompts. Missed it? Open System Settings > General > Login Items & Extensions > By Category > ⓘ next to Driver Extensions, and turn on `.Karabiner-VirtualHIDDevice-Manager.app`.
2. **Skip sudo** by joining the `virtual-hid` group, then open a new terminal:

   ```sh
   sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
   ```

## Usage

Input goes to whichever app is focused.

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

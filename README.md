# iPhone Use

Let an AI agent use a real iPhone from your Mac. Nothing is installed on the phone.

iPhone Use is a small macOS app. It reads the iPhone's screen over a USB cable and
taps and types through Bluetooth, posing as a keyboard and mouse. Your agent gets
an MCP server (and a plain HTTP API) with `screenshot`, `tap`, `swipe`, `type_text`,
`press_key` and `home`.

Because it drives a real, unlocked iPhone the way a person would, apps behave the
way they do in your hand: your accounts, App Store installs, push notifications,
iMessage. No simulator, no developer account, no app on the phone.

## How it works

```
                USB cable: screen frames (CoreMediaIO, like QuickTime)
   ┌──────────┐ ◀──────────────────────────────────────────────── ┌────────┐
   │   Mac    │                                                    │ iPhone │
   │iPhone Use│ ─────────────────────────────────────────────────▶ │        │
   └──────────┘   Bluetooth LE: keyboard + mouse (HID over GATT)   └────────┘
        ▲                                                   AssistiveTouch turns
        │ MCP / HTTP                                        the pointer into taps
     your agent
```

- **Screen.** A trusted iPhone becomes a video capture device once a Mac app sets
  `kCMIOHardwarePropertyAllowScreenCaptureDevices`. iPhone Use keeps the latest frame.
- **Input.** The Mac publishes a Bluetooth LE HID service with `CBPeripheralManager`.
  The iPhone pairs with it like any keyboard. Classic Bluetooth HID is not an option
  on current macOS because `bluetoothd` owns its L2CAP channels.
- **Taps.** With AssistiveTouch on, iOS shows a pointer for mice. iPhone Use's report
  map has an absolute pointer (X and Y from 0 to 32767) that iOS maps straight to the
  screen, so a tap lands exactly where it is aimed, no calibration. iOS ignores the
  absolute pointer's buttons, so the click itself goes through a second, relative
  mouse.
- **Typing.** A standard keyboard report, US layout.

## Requirements

- A Mac with Bluetooth LE (any Apple Silicon Mac). Tested on macOS 26.
- An iPhone and a USB **data** cable. Charge-only cables give power and no screen.
- Xcode command line tools to build.

## Setup

```sh
git clone https://github.com/xhoantran/iphone-use && cd iphone-use
./scripts/build-app.sh            # builds build/iPhoneUse.app
open build/iPhoneUse.app          # allow Bluetooth and Camera when asked
```

Then, once:

1. **Plug the iPhone in**, unlock it and tap **Trust**. On Apple Silicon, if the Mac
   asks "Allow accessory to connect?", click **Allow**. If the screen never shows up,
   check System Settings > Privacy & Security > *Allow accessories to connect*.
2. On the iPhone, **Settings > Bluetooth**: tap **iPhone Use** to pair.
3. On the iPhone, **Settings > Accessibility > Touch > AssistiveTouch**: turn it on.

Check it:

```sh
curl localhost:7390/status
# {"bluetooth":"connected","hosts":["..."],"screen":{"name":"iPhone","width":1180,"height":2556}}
```

iPhone Use runs as a menu-less background app. Quit it with `pkill -x iphone-use`.

## Use it from an agent (MCP)

The same binary is the MCP server. It talks to the running app over localhost.

Claude Code:

```sh
claude mcp add iphone-use -- "$PWD/build/iPhoneUse.app/Contents/MacOS/iphone-use" mcp
```

Any other MCP client:

```json
{
  "mcpServers": {
    "iphone-use": {
      "command": "/path/to/iPhoneUse.app/Contents/MacOS/iphone-use",
      "args": ["mcp"]
    }
  }
}
```

Screenshots are scaled so the long edge is 1200 px. Tap and swipe coordinates are
pixels of that screenshot. Every action returns a fresh screenshot.

| Tool | Arguments |
| --- | --- |
| `screenshot` | |
| `tap` | `x`, `y` |
| `long_press` | `x`, `y`, `seconds` |
| `swipe` | `x1`, `y1`, `x2`, `y2`, `seconds` |
| `type_text` | `text` (ASCII) |
| `press_key` | `key`, `modifiers` (`cmd`, `shift`, `alt`, `ctrl`) |
| `home` | |

`press_key` with `space` + `cmd` opens Spotlight, which is often the fastest way to
open an app: Spotlight, type the name, `enter`.

## HTTP API

Everything listens on `127.0.0.1:7390` (set `IPHONE_USE_PORT` to change it).
Coordinates are pixels of the full-resolution screen unless you pass `width` and
`height` for the image they came from, or `"fraction": true` for 0 to 1.

```sh
curl localhost:7390/screenshot -o screen.jpg                  # ?format=png, ?maxWidth=600
curl -X POST localhost:7390/tap   -d '{"x":590,"y":1278}'
curl -X POST localhost:7390/swipe -d '{"x1":590,"y1":1900,"x2":590,"y2":700,"duration":0.4}'
curl -X POST localhost:7390/type  -d '{"text":"hello"}'
curl -X POST localhost:7390/key   -d '{"key":"space","modifiers":["cmd"]}'
curl -X POST localhost:7390/home
```

`scripts/record.sh demo.mp4` records the phone screen until you press Ctrl-C.

## Limits

- One iPhone per Mac for now. BLE can hold several phones, and iPhone Use can
  address each one, but matching a Bluetooth host to a USB screen is not built yet.
- Typing is US ASCII. Other characters need the clipboard (not built yet).
- Portrait only has been tested.
- The phone must stay unlocked. Set Auto-Lock to Never while an agent is working.

## Credits

The idea comes from [TapKit](https://tapkit.ai). The hard parts of being a BLE
keyboard with CoreBluetooth (the long-form `1812` UUID, encrypted attributes, the
Report Reference descriptor) are written up in
[sryo/clak's notes](https://github.com/sryo/clak/blob/main/docs/corebluetooth-hid-notes.md).

## License

MIT

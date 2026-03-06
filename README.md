# TS-890 Pro

A macOS app for remotely operating a Kenwood TS-890S (and compatible TS-series radios) over a local network. Designed to be fully accessible with VoiceOver.

## Features

- Full CAT transceiver control (VFO, mode, filter, split, RIT/XIT, memory channels)
- LAN audio receive and transmit (Kenwood KNS VoIP protocol, UDP port 60001)
- USB serial CAT via CP2102N / Silicon Labs adapter
- Software noise reduction (RNNoise, WDSP EMNR, WDSP ANR)
- Receive and transmit audio equalizer
- Memory channel browser (read, recall, program)
- MIDI VFO tuning (CTR2MIDI and compatible encoders)
- Digital mode integration (WSJT-X / FT8 — USB-DATA mode + USB audio routing)
- Connection profiles for multiple radios or account types
- VoiceOver-first design — every control is labeled and keyboard accessible

## Requirements

- macOS 14 Sonoma or later
- Kenwood TS-890S with KNS (Kenwood Network System) enabled on the radio's LAN menu
- The radio's IP address and KNS administrator ID/password

---

## Installation

### Option 1 — Download a pre-built binary (easiest)

1. Go to the [Releases](https://github.com/w9fyi/ts-890-pro/releases) page.
2. Download the latest `Kenwood.control.zip`.
3. Unzip it and drag **Kenwood control.app** to your `/Applications` folder.
4. On first launch, macOS will show a Gatekeeper warning because the app is not notarized.
   - Right-click (or Control-click) the app icon and choose **Open**, then click **Open** in the dialog.
   - You only need to do this once.

### Option 2 — Build from source

**Prerequisites**

- Xcode 16 or later (free from the Mac App Store)
- `libfftw3` — install via [Homebrew](https://brew.sh):

```
brew install fftw
```

**Steps**

1. Clone the repository:

```
git clone https://github.com/w9fyi/ts-890-pro.git
cd ts-890-pro
```

2. Open the project in Xcode:

```
open "Kenwood control.xcodeproj"
```

3. In Xcode, select the **Kenwood control** scheme and your Mac as the destination.
4. Press **Command-B** to build, or **Command-R** to build and run.

The app will be signed with your local development certificate, so Gatekeeper will not block it.

---

## Getting Started

See the full [User Manual](docs/UserManual.md) for step-by-step setup instructions, including:

- KNS setup on the radio
- Connecting and authenticating
- Audio setup and noise reduction
- MIDI tuning
- Keyboard shortcuts
- VoiceOver and accessibility notes
- Troubleshooting

---

## License

Source code is provided for personal and amateur radio use. See [LICENSE](LICENSE) if present, or contact the author via GitHub.

## Author

AI5OS / WB2WGH — [GitHub](https://github.com/w9fyi)

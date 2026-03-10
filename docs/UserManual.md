# TS-890 Pro — User Manual

**TS-890 Pro** is a macOS app for remotely operating a Kenwood TS-890S over a local network or USB cable. It provides full transceiver control, LAN and USB audio, software noise reduction, FreeDV digital voice, WSJT-X digital mode integration, KNS server administration, memory management, a bandscope/waterfall display, MIDI tuning, and VoiceOver-first accessibility throughout.

---

## Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [First Launch](#first-launch)
4. [Connection — LAN/KNS](#connection--lankns)
5. [Connection — USB Serial](#connection--usb-serial)
6. [Connection Profiles](#connection-profiles)
7. [Radio Controls](#radio-controls)
8. [TX Audio and PTT](#tx-audio-and-ptt)
9. [LAN RX Audio](#lan-rx-audio)
10. [USB Audio Monitor](#usb-audio-monitor)
11. [Software Noise Reduction](#software-noise-reduction)
12. [Equalizer](#equalizer)
13. [FreeDV Digital Voice](#freedv-digital-voice)
14. [FT8 / WSJT-X Integration](#ft8--wsjt-x-integration)
15. [Bandscope and Waterfall](#bandscope-and-waterfall)
16. [Front Panel View](#front-panel-view)
17. [Memory Browser](#memory-browser)
18. [EX Menu Access](#ex-menu-access)
19. [KNS Administration](#kns-administration)
20. [MIDI Tuning](#midi-tuning)
21. [Keyboard Shortcuts](#keyboard-shortcuts)
22. [Settings](#settings)
23. [Logs and Diagnostics](#logs-and-diagnostics)
24. [VoiceOver and Accessibility](#voiceover-and-accessibility)
25. [Troubleshooting](#troubleshooting)

---

## Requirements

- macOS 14 Sonoma or later (macOS 15 Sequoia or macOS 26 recommended)
- Kenwood TS-890S connected to the same local network **or** connected via USB
- For LAN/KNS operation: KNS enabled in the radio's LAN menu, with an administrator ID and password set
- For USB operation: Silicon Labs CP2102N driver installed — download from the Kenwood website
- The radio's IP address (check the radio's LAN menu or your router's DHCP table)

### Intel Mac Users

The pre-built binary is compiled for Apple Silicon. It runs on Intel Macs via **Rosetta 2** with no setup beyond the normal first-launch steps. When you open the app for the first time on an Intel Mac, macOS will offer to install Rosetta 2 — click **Install**, then open the app again. Performance is identical for this type of application.

---

## Installation

1. Download `TS-890.Pro.zip` from the [GitHub releases page](https://github.com/w9fyi/ts-890-pro/releases).
2. Unzip and drag **TS-890 Pro.app** to your Applications folder.
3. On first launch, **right-click → Open** to bypass Gatekeeper (the binary is unsigned). You only need to do this once.
4. macOS will ask for network access — allow it.
5. **Intel Mac:** if macOS prompts to install Rosetta 2, click **Install**, then reopen the app.

To build from source, clone the repository and run:

```
xcodebuild -scheme "TS-890 Pro" -configuration Release build
```

---

## First Launch

The app opens to the **Connection** section. Before controlling the radio you need to provide either:

- **LAN/KNS:** the radio's IP address, TCP port (default 60000), and your KNS credentials
- **USB:** the serial port path for the radio's CAT interface

Credentials entered for LAN are saved per host in the macOS Keychain and remembered for future sessions.

---

## Connection — LAN/KNS

Navigate here with **Command-1** or select **Connection** in the sidebar.

### Fields

| Field | Description |
|---|---|
| Host / IP | IP address or hostname of the radio (e.g. `192.168.1.20`) |
| Port | TCP port — use **60000** for direct KNS control |
| Use KNS Login | Enable for authenticated KNS sessions (required for all TS-890S radios) |
| KNS Account Type | **Admin** or **User** — admin allows full control including EX menu and KNS administration |
| Admin ID | The administrator ID set in the radio's LAN menu |
| Password | The administrator password (stored in the macOS Keychain) |

Once credentials are saved, a compact summary line ("Credentials saved for …") appears with an **Edit Credentials…** button to change them.

### Buttons

- **Connect** — opens the TCP connection and performs KNS authentication
- **Disconnect** — closes the connection and stops LAN audio
- **KNS Setup Wizard** — opens a step-by-step sheet for first-time setup

### Connection Status

| State | Meaning |
|---|---|
| Disconnected | Not connected |
| Connecting | TCP handshake in progress (15-second timeout) |
| Authenticating | KNS login exchange in progress (10-second timeout) |
| Connected | Fully authenticated and ready |

If an error occurs (wrong password, radio unreachable, timeout) it is shown in red below the status line. Pressing **Connect** again clears the error and retries.

### KNS Setup Wizard

The wizard walks through enabling KNS on the radio for the first time:

1. On the radio, open the LAN menu and set KNS to LAN Only or Internet.
2. Set an administrator ID (1–32 characters, ASCII only) and password.
3. Note the radio's IP address from the LAN menu.
4. Enter the details in the wizard and press **Test Connection**.

---

## Connection — USB Serial

The app can control the radio directly over USB using the TS-890S CAT serial port (the Silicon Labs CP2102N USB-to-UART bridge).

### Setup

1. Connect the TS-890S to the Mac with a USB-B cable (the Standard USB port on the radio's rear panel).
2. Install the Silicon Labs CP2102N driver if prompted.
3. In the **Connection** section, enable **Use USB Serial**.
4. The port auto-detects as `cu.SLAB_USBtoUART` — the app uses the by-id path to remain stable across reboots.
5. Baud rate is fixed at **115200 bps** (8N1), matching the TS-890S Enhanced port defaults.
6. Press **Connect** — the app opens the serial port and begins CAT communication.

### USB vs. LAN

USB serial provides CAT control only — no audio and no KNS-specific commands (##KN series). For receive audio over USB, use the **USB Audio Monitor** section. For transmit audio over USB, use the **Operator Audio Settings** sheet in the TX Audio section.

Both connections can be used simultaneously if needed (e.g. LAN audio + USB CAT), though the app is typically used in one mode at a time.

---

## Connection Profiles

Select **Profiles** in the Settings window or sidebar.

Profiles save a complete connection configuration — host, port, KNS settings, account type, and credentials — under a friendly name. Useful if you connect to more than one radio or switch between admin and user accounts.

### Creating a Profile

1. Press **Add Profile** — the editor sheet opens pre-filled with the current connection settings.
2. Give it a name (e.g. "Home Radio — Admin").
3. Adjust the host, port, and credentials as needed.
4. Press **Save** — the password is stored in the macOS Keychain, not in the profile itself.

### Using a Profile

Select a profile in the list and press **Connect** — the app applies all settings and connects immediately.

### Editing and Deleting

- **Edit** — opens the editor sheet for a profile.
- Swipe left or press Delete to remove a profile.

---

## Radio Controls

Navigate here with **Command-2** or select **Radio** in the sidebar.

### VFO

| Control | Description |
|---|---|
| VFO A MHz | Enter a frequency in MHz and press Return or **Set VFO A** |
| VFO B MHz | Enter a frequency in MHz and press Return or **Set VFO B** |
| Band Up / Band Down | Step through amateur bands |

Frequencies are displayed and accepted in MHz to six decimal places (e.g. `14.225000`). Fields update automatically as the radio reports frequency changes via Auto Information.

### Memory Channels

- **Memory Mode** toggle — switches between VFO and memory channel operation
- **Channel** field + stepper — select a memory channel (0–119)
- **Recall** button — activates the selected channel
- The channel's name, frequency, and mode are shown to the right

#### Program Memory

Fill in a frequency, mode, and optional name (up to 10 characters), then press **Program This Channel** to write it to the currently selected memory slot. **Use Current VFO A** copies the active frequency and mode into the program fields.

### Split Operation

- **Split** toggle — enables split TX/RX
- **RX VFO** / **TX VFO** pickers — assign VFOs to receive and transmit
- **Split Offset** — enter a kHz value and press **+** or **–** to offset the TX VFO

### RIT / XIT

- **RIT** toggle — receive incremental tuning
- **XIT** toggle — transmit incremental tuning
- **Offset slider** — −9999 to +9999 Hz; **Clear** returns to zero

### RX Filter

Three controls adjust the receive filter passband in real time:

- **Low Cut** (0–35)
- **High Cut** (0–27)
- **Filter Shift** (−9999 to +9999 Hz)

All three send CAT commands immediately as you drag.

### TX Power and ATU

- **Power (W)** slider — 5–100 W, applies immediately
- **ATU TX** toggle — enables the internal antenna tuner on transmit
- **Tune** / **Stop Tune** — start and stop an ATU tuning cycle

### Gains

- **RF Gain** (0–255)
- **AF Gain** (0–255)
- **Squelch** (0–255)

All have both a slider and a numeric text field for direct entry.

### Operating Mode

Select mode from the full picker (LSB, USB, CW, CW-R, FSK, FSK-R, AM, FM) or use the quick **LSB** / **USB** buttons. Keyboard shortcuts for common modes are listed in the [Keyboard Shortcuts](#keyboard-shortcuts) section.

### DSP Functions

- **NR** — the radio's built-in noise reduction: Off, NR1, or NR2
- **Notch** — the radio's auto-notch filter

Software noise reduction (running on the Mac, not the radio) is in its own section — see [Software Noise Reduction](#software-noise-reduction).

---

## TX Audio and PTT

### PTT

- **PTT Down (TX)** / **PTT Up (RX)** buttons — key and unkey the transmitter
- **Hold Option-Space** — push-to-talk from the keyboard; release to return to receive
- PTT is automatically released when the app loses focus

### TX Audio Source

Press **Operator Audio Settings…** in the TX row to open the audio source sheet:

| Setting | Description |
|---|---|
| Microphone (MS001) | The radio's physical microphone connector — default for voice operation |
| USB Passthrough (MS002) | Routes Mac microphone audio to the radio's USB Codec input — for digital modes or remote mic |
| LAN Audio (MS003) | KNS VoIP audio — used automatically by FreeDV LAN mode |

**USB Passthrough** captures audio from the selected Mac input device (e.g. the built-in microphone or a USB headset) and sends it to the TS-890S over the USB audio interface. CoreAudio HAL is used to route audio between the Mac and the radio's USB Codec at low latency.

**Revert** — returns the audio source to Microphone (MS001).

### VoIP Levels (LAN audio)

When operating over KNS/LAN:

| Control | Description |
|---|---|
| VoIP Volume | Receive audio level sent by the radio (0–100) |
| VoIP Mic | Microphone level for transmitting over KNS (0–100) |

If PTT keys but there is no modulation, raise VoIP Mic above 0 (try 50).

---

## LAN RX Audio

Select **Audio** in the sidebar (or navigate via **Command-3**).

The radio streams receive audio over UDP port 60001 using Kenwood's VoIP protocol. The app decodes this stream and plays it through the selected Mac output device.

| Control | Description |
|---|---|
| Auto-start LAN audio | Starts audio automatically on connect |
| Output picker | Mac speaker, headphone, or audio interface to play through |
| Refresh Audio Devices | Re-scans for newly connected audio devices |
| Volume slider (0.1–4.0) | Software gain on received audio |
| Running / Stopped | Current state of the UDP audio receiver |

**Packet count** and **last packet time** are shown for diagnostics. If the count is not advancing, the radio is not streaming — check that KNS VoIP is enabled (the app sends `##VP1;` on connect). The receiver stays bound to its UDP port across TCP reconnects so audio survives brief connection drops.

---

## USB Audio Monitor

When connected via USB serial, the TS-890S USB Codec provides a low-latency audio path from the radio directly to the Mac.

In the **Audio** section, enable **USB Audio Monitor** to:

- Route TS-890S USB audio output to the selected Mac output device
- Apply the same software noise reduction pipeline as LAN audio
- Monitor the radio without needing a LAN connection or KNS

The USB audio monitor uses CoreAudio to capture from the TS-890S USB Codec input device. Select the correct device from the **USB Audio Input** picker if more than one USB audio device is connected.

---

## Software Noise Reduction

Available in the **Audio** section for both LAN and USB audio paths.

- **Enable** toggle — turns software NR on/off (keyboard: **Command-Shift-N**)
- **NR Profile** picker — **Speech** (optimised for voice) or **Static Hiss** (broadband noise)
- **NR Strength** slider (0–100%) — how aggressively noise is removed
- **Backend** picker — choose the NR engine:

| Backend | Description |
|---|---|
| RNNoise | Neural-network noise suppression; best for voice with background noise |
| WDSP EMNR | Extended Modulation Noise Reduction from the OpenHPSDR WDSP library |
| WDSP ANR | Adaptive Noise Reduction from WDSP |

Use **Command-Control-R** to cycle through backends during operation.

---

## Equalizer

Select **Equalizer** in the sidebar.

Adjusts the radio's receive audio equalizer bands via CAT. Sliders send changes immediately as you drag. Three bands are available (low, mid, high), each covering the radio's receive EQ range.

---

## FreeDV Digital Voice

Select **FreeDV** in the sidebar.

FreeDV is an open digital voice mode that provides intelligible voice at lower SNR than SSB. TS-890 Pro integrates the codec2/FreeDV library directly.

### Modes

| Mode | Codec | Use case |
|---|---|---|
| FreeDV 1600 | Codec2 1300 | Standard HF digital voice |
| FreeDV 700D | Codec2 700C | Low SNR conditions |
| FreeDV 2020 | LPCNet | Wider bandwidth, higher quality |

### LAN Audio (KNS)

When connected via LAN, FreeDV uses the KNS VoIP audio path:

- **RX:** radio LAN audio → FreeDV decoder → Mac speakers
- **TX:** Mac microphone → FreeDV encoder → LAN audio (`MS003;`)

Press **Start FreeDV RX** to begin decoding received audio. Press **PTT** or hold Option-Space to transmit.

### USB Audio

When connected via USB serial, FreeDV uses the TS-890S USB Codec:

- **RX:** USB audio input → FreeDV decoder → Mac speakers
- **TX:** Mac microphone → FreeDV encoder → USB audio output (`MS002;`)

### Controls

| Control | Description |
|---|---|
| Mode picker | FreeDV 1600 / 700D / 2020 |
| Audio path | LAN or USB |
| SNR display | Received SNR in dB |
| Sync indicator | Shows whether the FreeDV modem has locked onto a signal |
| Revert Audio Source | Returns the radio's TX audio source to Microphone (`MS001;`) after a FreeDV session |

---

## FT8 / WSJT-X Integration

Navigate here with **Command-5** or select **FT8** in the sidebar.

TS-890 Pro provides one-press setup for FT8 operation on each band:

- **Band buttons** — jump to the standard FT8 calling frequency for 160m through 10m
- **WSJT-X Mode** button — switches the radio to USB-DATA (`OM0D;`) and sets TX audio to USB Codec (`MS002;`)
- **Revert** — returns to the previous mode and Microphone audio source

### WSJT-X Setup

1. Launch WSJT-X. Set the rig to **Hamlib NET rigctl**, host `localhost`, port `4532`.
2. Start `rigctld` (part of Hamlib) with the TS-890S serial port or the KNS TCP address.
3. In TS-890 Pro, press **WSJT-X Mode** to configure the radio.
4. WSJT-X handles TX scheduling; TS-890 Pro handles mode/audio routing.

The radio's Enhanced USB port (`cu.SLAB_USBtoUART7`) is recommended for WSJT-X PTT to avoid interfering with the app's CAT stream on the Standard port.

---

## Bandscope and Waterfall

Select **Scope** in the sidebar.

The bandscope displays real-time spectrum data streamed from the radio via the `DD1` command (LAN high-cycle output). The waterfall below accumulates the spectrum history.

| Control | Description |
|---|---|
| Span picker | Scope span: ±2.5 kHz to ±500 kHz |
| Center / Fixed / Auto Scroll | Scope mode (mirrors the radio's scope mode) |
| Peak Hold | Overlay the peak spectrum trace |
| Waterfall speed | How fast new lines scroll (1–10) |
| VFO A marker | Red vertical line showing VFO A position |
| Filter overlay | Shaded region showing the active RX passband |

The bandscope only streams while the radio is connected and `DD1` output is enabled. The scope data arrives separately from the CAT command stream and does not affect CAT responsiveness.

---

## Front Panel View

Select **Front Panel** in the sidebar.

A touchscreen-inspired layout that mirrors the physical controls of the TS-890S front panel. Useful for mouse or trackpad operation when you want a more radio-like visual interface rather than the app's sectioned controls.

All controls in the front panel view send the same CAT commands as their equivalents in the Radio section. Changes made in one view are immediately reflected in the other.

---

## Memory Browser

Select **Memories** in the sidebar.

A full list of all 120 memory channels read from the radio. Select a channel in the list to see its frequency, mode, and name. Double-tap or press **Recall** to activate the channel. Use the search field to filter by name or frequency.

Press **Reload All** to re-read the full memory contents from the radio (takes a few seconds for all 120 channels).

---

## EX Menu Access

Select **Menu Access** in the sidebar.

Provides direct read/write access to the TS-890S extended menu (EX command) without using the front panel. All 125 verified EX menu items are listed, cross-referenced against the Kenwood CAT reference.

### Full Menu Mode

Items are organised into collapsible groups matching the radio's menu categories. For each item:

- **Read** — queries the radio and displays the current value
- **Value field** — enter a new value
- **Write** — sends the new value to the radio; takes effect immediately (no front-panel save step needed)
- **Refresh Visible** — reads all currently visible items at once

Use the **Search** field to filter by item name, number, or group.

### Discover Mode

Scans EX items 0–1100, recording which ones the radio responds to. Takes about 25 seconds. Useful for verifying which items are active on a particular firmware version, or finding items not in the definitions list.

- **Start Scan** — begins the scan (radio must be connected)
- **Stop** — aborts the scan
- **Copy Results** — copies all discovered items as `EX0xxxx nnn [label]` lines to the clipboard

### Custom Menu Number

Enter any EX item number directly to read or write it without searching the list — useful for items outside the 0–999 range (advanced menu items start at 10000).

---

## KNS Administration

Open **Settings** (Command-comma) and select the **KNS Admin** tab.

Allows full management of the radio's built-in KNS server without touching the front panel. Requires an active **administrator** login — all controls are disabled if connected as a user account.

Press **Refresh** in the toolbar to re-read all KNS settings from the radio.

### KNS Settings Tab

| Control | Description |
|---|---|
| KNS Mode | Off / LAN Only / Internet |
| Session Timeout | 1–120 minutes or Unlimited |
| Mute Speaker During Remote Operation | Silences the radio's speaker when a remote client is connected |
| KNS Operation Access Log | Records connection events in the radio's internal log |
| Allow Registered User Remote Operations | Lets User-account logins perform TX operations |
| Welcome Message | Up to 128 characters, shown to clients on connect |

### VoIP Tab

| Control | Description |
|---|---|
| Built-in VoIP Enabled | Master switch for the radio's VoIP function |
| VoIP Input Level | 0–100, controls how loud the remote audio is sent to the radio |
| VoIP Output Level | 0–100, controls the radio's received audio level sent to the client |
| Jitter Buffer | 80 / 200 / 500 / 800 ms — increase on unreliable network links |

### Users Tab

The Users tab manages the radio's registered KNS user accounts (slots 000–099).

- **Load Users** — reads all registered user entries from the radio
- **Add User** — opens the editor sheet to create a new account
- Each user row shows the account number, user ID, and any badges (RX Only, Disabled)
- **Edit** — modify an existing user's ID, password, description, and permissions
- **Delete** — permanently removes the user from the radio

#### User Editor Fields

| Field | Limit | Description |
|---|---|---|
| User ID | 32 chars | Login ID for KNS authentication |
| Password | 32 chars | Login password |
| Description | 128 chars | Optional label for identification |
| RX Only | — | Prevents the user from transmitting |
| Temporarily Disabled | — | Blocks login without deleting the account |

### Admin Tab

**Change Administrator Credentials** — enter the current admin ID and password, then the new ID and password, and press **Apply**. The radio updates its stored administrator account immediately.

**Change Your Password** — changes the password for the currently logged-in account without requiring the current password to be re-entered.

Results (success or failure) are shown in green or red below the form.

---

## MIDI Tuning

Select **MIDI** in the sidebar.

Use a MIDI rotary encoder (such as the Lynovations CTR2) to tune VFO A with a hardware knob.

### Setup

1. Connect the MIDI device to the Mac.
2. Press **Refresh Sources** to scan for MIDI input devices.
3. Select the device from the **MIDI Source** picker.
4. Set the **MIDI Channel** (1–16) and **CC Number** (0–127) to match what the encoder sends.
5. Press **Save CC Settings** to persist the configuration across app launches.

### Tuning Step

| Step | Use case |
|---|---|
| 10 Hz | Precise CW/SSB tuning |
| 100 Hz | Normal SSB tuning |
| 1 kHz | Quick in-band moves |
| 10 kHz | Band scanning |
| 100 kHz | Fast band changes |

### How Relative Encoders Work

The CTR2 and similar encoders send relative CC values:
- Clockwise: CC value 1–63 (larger = faster spin)
- Counter-clockwise: CC value 65–127

The **Last MIDI Event** display shows the most recent CC message received — use it to verify the device is connected and sending the correct channel and CC number.

---

## Keyboard Shortcuts

### Section Navigation

| Shortcut | Section |
|---|---|
| Command-1 | Connection |
| Command-2 | Radio |
| Command-3 | Audio |
| Command-4 | Logs |
| Command-5 | FT8 |

### Connection

| Shortcut | Action |
|---|---|
| Command-C | Connect (with saved credentials) |
| Command-D | Disconnect |

### Audio

| Shortcut | Action |
|---|---|
| Command-Shift-N | Toggle software noise reduction |
| Command-Control-R | Cycle noise reduction backend |
| Command-Shift-M | Toggle audio mute |

### Operating Mode

| Shortcut | Mode |
|---|---|
| Control-Shift-L | LSB |
| Control-Shift-U | USB |
| Control-Shift-C | CW |
| Control-Shift-A | AM |
| Control-Shift-F | FM |

### PTT

| Shortcut | Action |
|---|---|
| Hold Option-Space | PTT down — release to return to receive |

PTT is automatically released if the app loses focus or the Option key is released.

### Customising Shortcuts

Open **Settings → Keyboard Shortcuts** to view all registered shortcuts and reassign them. Changes persist across launches.

---

## Settings

Open Settings with **Command-comma** or from the app menu.

Settings is a tabbed window with the following sections:

| Tab | Contents |
|---|---|
| General | App-wide preferences: auto-connect on launch, default audio device |
| Audio | Default input/output device selection, volume defaults |
| Profiles | Connection profile management (same as the Profiles section) |
| KNS Admin | KNS server administration — see [KNS Administration](#kns-administration) |
| Logs | Diagnostic log viewer and export |
| Menu Access | EX menu browser — same as the sidebar section |

---

## Logs and Diagnostics

Navigate here with **Command-4** or select **Logs** in the sidebar.

### Status Summary

Shows connection state, VFO A frequency, operating mode, and the last transmitted and received CAT frames in a monospaced display.

### Connection Log

A scrollable, timestamped list of connection events: authentication steps, errors, keepalive frames, and mode changes. Press **Copy Log** to paste the full log for troubleshooting. **Clear** empties the list.

### Smoke Test

Press **Run Smoke Test** to send a sequence of diagnostic CAT commands and verify the radio responds correctly. Results are shown immediately in the status field.

### Log File

A persistent log is written to `~/Downloads/Kenwood control/kenwood-control.log`. It includes connection events, audio pipeline state, PTT transitions, NR diagnostics, and CAT frame traces. Use any text viewer to inspect it.

---

## VoiceOver and Accessibility

TS-890 Pro is designed to be fully operable with VoiceOver from first launch.

### What is accessible

- Every control has an `accessibilityLabel` describing its purpose
- Sliders announce their current value in natural language units (e.g. "2400 hertz", "75 watts")
- All status changes — connect, disconnect, error messages, PTT state — are announced without requiring focus to move
- Error messages appear directly below the status line in the Connection section so VoiceOver reads them without navigating to the Logs tab
- All section navigation is available via Command-1 through Command-5 — the sidebar list never needs to be navigated
- All sliders have a corresponding text field for direct numeric entry
- Decorative status indicators (coloured circles, scope graphics) are hidden from the accessibility tree
- List rows (memory channels, KNS users, connection profiles) announce their full content as a combined label

### PTT under VoiceOver

Option-Space PTT works under VoiceOver. The app tracks Option key state independently to handle cases where VoiceOver captures modifier events before the app sees them.

### Audio monitoring without a screen

The USB Audio Monitor and LAN audio sections can be started entirely from the keyboard. Once configured, the app remembers the device selection and restores it on next launch. Noise reduction can be toggled with Command-Shift-N from anywhere in the app without entering the Audio section.

### Controls that are screen-independent

The following work entirely without visual inspection:
- Frequency entry (type MHz → press Return)
- Mode selection (keyboard shortcuts)
- PTT (Option-Space)
- Noise reduction toggle (Command-Shift-N)
- Connect / Disconnect (Command-C / Command-D)
- MIDI tuning (hardware encoder → radio with no app interaction)

---

## Troubleshooting

### Cannot connect — "Connection timed out"

- Verify the radio's IP address in the LAN menu (`Menu → LAN → IP Address`).
- Confirm KNS is set to LAN Only or Internet in the radio's LAN menu.
- Make sure TCP port 60000 is not blocked by a firewall between the Mac and the radio.
- The radio must be powered on — it does not respond to KNS from standby-off.
- If connecting over Wi-Fi, try a wired connection to rule out packet loss.

### Authentication failed — "check Admin ID and password"

- Use **Edit Credentials…** to re-enter and try again.
- IDs and passwords are ASCII only, 1–32 characters. Check for invisible trailing spaces.
- Confirm the correct account type (Admin or User) is selected.
- If the credentials were recently changed from the front panel, update them in the app.

### Connected but no LAN audio

- Verify **Auto-start LAN audio** is on, or check that the Audio section shows **Running**.
- Check the **Output** picker is set to the correct device. Press **Refresh Audio Devices** if a device was connected after launch.
- Volume slider must be above 0.1.
- On the radio, confirm KNS VoIP is enabled (the app sends `##VP1;` on connect; check the Logs section to verify).
- If **LAN Audio Error** shows "port in use", another app or a previous session is holding UDP port 60001 — quit other radio apps and try again.

### PTT keys but no audio transmitted (LAN)

- Raise **VoIP Mic** above 0 in the Audio section (try 50).
- Confirm the correct **Mic Input** is selected.
- Check TX audio source is set to LAN Audio (`MS003;`) in Operator Audio Settings.

### PTT keys but no audio transmitted (USB Passthrough)

- Confirm TX audio source is set to USB Passthrough (`MS002;`) in Operator Audio Settings.
- Check macOS microphone privacy — go to System Settings → Privacy → Microphone and enable TS-890 Pro.
- Confirm the correct Mac input device is selected in Operator Audio Settings.

### USB serial not connecting

- Verify the Silicon Labs CP2102N driver is installed and the radio appears in `/dev/cu.SLAB_USBtoUART`.
- Make sure no other app (ARCP-890, fldigi, etc.) has the serial port open.
- Disconnect and reconnect the USB cable, then press Connect again.

### FreeDV: no sync / garbled audio

- Confirm the radio is in USB or USB-DATA mode.
- Check that the other station is transmitting the same FreeDV mode.
- Increase the radio's RF gain if the SNR display shows very low values.
- Jitter in the audio path can cause sync loss — raise the KNS jitter buffer if using LAN audio.

### MIDI encoder not tuning

- Press **Refresh Sources** in the MIDI section.
- Verify Channel and CC Number match — turn the encoder and watch **Last MIDI Event**.
- Press **Save CC Settings** and restart the app if settings were not previously saved.

### EX menu returns `?;`

- Some EX items cannot be changed while the radio is transmitting — try while in receive.
- A few items are read-only or firmware-dependent — the Discover scan will show which items your firmware responds to.

### Log file location

`~/Downloads/Kenwood control/kenwood-control.log`

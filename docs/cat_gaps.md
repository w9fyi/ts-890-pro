# TS-890 Pro — CAT Command Gap Analysis

**Source:** `ts-890-computer-control90_pc_command_en_rev1.md` (186 total command mnemonics)
**App baseline:** v1.3.0 (post CAT audit fixes, 2026-03-12)
**Purpose:** Identify commands in the PC Command Reference that are not yet implemented in the app, prioritized by user value.

**Status key:**
- `implemented` — present in KenwoodCAT.swift and/or RadioState.handleFrame
- `not implemented` — documented in reference, not in app
- `partial` — read OR write implemented but not both
- `legacy` — in app but not in reference (DA, MD — kept for parser compat only)

---

## Summary

| Category | Total in Reference | Implemented | Not Implemented |
|----------|-------------------|-------------|-----------------|
| Core radio control | ~65 | 45 | 20 |
| Signal processing / filters | ~30 | 8 | 22 |
| CW features | ~20 | 5 | 15 |
| VOX | 4 | 1 | 3 |
| Memory / scanning | ~25 | 6 | 19 |
| Bandscope (extended) | ~22 | 1 | 21 |
| FM / tone | 4 | 0 | 4 |
| Antenna / linear amp | ~10 | 1 | 9 |
| Voice messages / recording | ~12 | 0 | 12 |
| Timers / clock (extended) | ~10 | 3 | 7 |
| Network / display / misc | ~20 | 0 | 20 |
| **Total** | **186** | **~63** | **~123** |

---

## Tier 1 — High Value: Missing Core Controls

These are features that operators use regularly. Should be prioritized.

### VFO / Tuning

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `EC` | VFO A ↔ B Exchange | `EC;` (set only) | Swap VFO A and B. Extremely common. |
| `VV` | VFO A → B Copy (A=B) | `VV;` (set only) | Copy VFO A to B. |
| `FS` | FINE Function ON/OFF | `FSP1;` P1=0/1 | Fine tuning step toggle. |
| `MH` | MHz Step Function | `MHP1;` P1=0(off)/1(on) | 1 MHz step mode. |
| `UD` | VFO Frequency UP/DOWN | `UDP1P1;` | Step VFO up/down by current step size. |
| `BD` / `BU` | Band Down / Band Up | `BD;` / `BU;` | Jump to next/previous band. |
| `SF` | VFO Frequency + Mode (combined) | `SFP1P2P2...P3;` | Read/write VFO freq+mode in one command. |
| `FC` | Frequency via Tuning Control | `FCP1P2;` P1=dir, P2=steps | Simulate turning the main dial. |

### Lock / Mute

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `LK` | Lock ON/OFF | `LKP1;` P1=0/1 | Front panel lock. |
| `MU` | Mute (all audio) | `MUP1;` P1=0/1 | Mutes speaker + headphone output. |
| `QS` | Speaker Mute | `QSP1;` P1=0/1 | Speaker-only mute (headphones not muted). |

### Power

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `PS` | Power ON/OFF | `PSP1;` P1=0(off)/1(on)/…6 | Radio power state. Read returns current state. |
| `FV` | Firmware Version | `FV;` (read only) | Returns firmware version string. Useful for diagnostics. |

### Monitors

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `MO0` | TX Monitor ON/OFF | `MO0P1;` P1=0/1 | Toggle TX monitor (sidetone). |
| `MO1` | RX Monitor ON/OFF | `MO1P1;` P1=0/1 | Toggle RX monitor. |
| `MO2` | DSP Monitor ON/OFF | `MO2P1;` P1=0/1 | Toggle DSP monitor. |

---

## Tier 1 — High Value: Missing Signal Processing

### Noise Blanker 2 (completely absent)

The radio has two independent noise blankers. Only NB1 is implemented.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `NB2` | Noise Blanker 2 ON/OFF | `NB2P1;` P1=0/1 | Independent NB. Completely missing. |
| `NBT` | NB2 Type (A or B) | `NBTP1;` P1=0(A)/1(B) | Type A = pulse width, Type B = depth/width. |
| `NBD` | NB2 Type B Depth | `NBDP1P1P1;` 001–020, 999=auto | NB2 depth when type=B. |
| `NBW` | NB2 Type B Width | `NBWP1P1P1;` 001–020, 999=auto | NB2 width when type=B. |

### Noise Blanker Levels

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `NL1` | Noise Blanker 1 Level | `NL1P1P1P1;` 001–020, 999=auto | NB1 threshold depth. Can't adjust NB1 without this. |
| `NL2` | Noise Blanker 2 Level | `NL2P1P1P1;` 001–010, 999=auto | NB2 threshold depth. |

### Notch (manual position + bandwidth)

The app can toggle the notch but can't position it or set its width.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `BP` | Manual Notch Frequency | `BPP1P1P1;` 000–255 | Position of the auto/manual notch filter. |
| `NW` | Notch Bandwidth | `NWP1;` P1=0(narrow)/1(mid)/2(wide) | Width of the notch filter. |

### Noise Reduction Levels

The app can set NR mode (off/NR1/NR2) but can't tune the levels.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `RL1` | Noise Reduction 1 Level | `RL1P1P1;` 01–10, 99=auto | NR1 aggression level. |
| `RL2` | Noise Reduction 2 Time Constant | `RL2P1P1;` 00–09, 99=auto | NR2 time constant (higher = more aggressive). |

### Audio Peak Filter (APF) — completely absent

APF is a narrow bandpass filter centred on the CW pitch. Very useful for CW.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `AP0` | APF ON/OFF | `AP0P1;` P1=0(off)/1(A)/2(B) | Two APF memories. |
| `AP1` | APF Shift | `AP1P1P1P1;` 00–80, 99=centre | Frequency offset from CW pitch. |
| `AP2` | APF Pass Bandwidth | `AP2P1;` P1=0(wide)/1(mid)/2(narrow)/9=auto | Passband width. |
| `AP3` | APF Gain | `AP3P1;` P1=0–6, 9=auto | APF level boost. |

### AGC (extended)

The app has GC (0/1/2/3) but can't read/write the actual timing presets or quick-recovery.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `GT` | AGC Time Constant Presets | `GTP1P1P1P2P2P2P3P3P3;` | Read/write slow/mid/fast preset timing values. |
| `AQ0` | AGC Quick Recovery ON/OFF | `AQ0P1;` P1=0/1 | Fast signal drop recovery. |
| `AQ1` | AGC Quick Recovery Threshold | `AQ1P1P1;` 01–10, 99=auto | Level at which quick recovery triggers. |

### Filter Selection (roofing filter + shape + AF type)

The app handles FL0 (filter slot A/B/C) but not the roofing filter hardware selection, IF shape, or AF filter type.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `FL1` | Roofing Filter | `FL1P1P2P3;` P1=slot 0–2, P2/P3=filter | Hardware roofing filter selection per slot. |
| `FL2` | IF Filter Shape | `FL2P1P2;` P1=slot 0–2, P2=flat/sharp | DSP IF filter shape factor. |
| `FL3` | AF Filter Type | `FL3P1P2;` P1=slot 0–2, P2=type 0–3 | AF output filter type. |

### FM Filter Width

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `FW` | FM Normal/Narrow | `FWP1P2;` P1=0(read left)/1(right), P2=0(normal)/1(narrow) | FM filter width. Needed for FM/repeater ops. |

### Speech Processor (extended)

The app has PR0 (on/off) but not the I/O levels or effect type.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `PL` | Speech Processor I/O Level | `PLP1P1P1P2P2P2;` 000–100 each | Read/write input level and output level. |
| `PR1` | Speech Processor Effect Type | `PR1P1;` P1=0(through)/1(mic EQ)/2(compression)/3(both) | SP processing mode. |

### DATA VOX

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `DV` | DATA VOX ON/OFF | `DVP1;` P1=0–3 | VOX triggered by data/digital audio. Needed for digital modes. |

---

## Tier 1 — High Value: Missing CW Controls

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `CA` | CW Auto Tune | `CAP1;` P1=0(off)/1(on) | Automatic zero-beat tuning in CW mode. |
| `PT` | CW Pitch / Sidetone Frequency | `PTP1P1P1;` 000–160 → 300–1100 Hz | CW pitch offset and sidetone pitch. Formula: Hz = 300 + (P1 × 5). |
| `SD` | CW Break-in Delay | `SDP1P1P1P1;` 0000–1000 ms | Delay between last key and TX→RX switch. |

### CW Message Memory (8 channels)

| Command | Description | Notes |
|---------|-------------|-------|
| `CM0` | Register CW message (paddle) | Stores live paddle input into a channel |
| `CM1` | Play/stop CW message | Transmit stored message |
| `CM2` | Registration state readout | Which channels have messages |
| `CM3` | Clear CW message | Erase a channel |
| `CM4` | CW message channel name | Read/write name for each channel |
| `CM5` | Register CW message (text input) | Store text as CW message |
| `CM6` | CW message repeat | Loop playback on/off per channel |
| `CM7` | Contest number | Read/write/increment contest serial number |

### CW Decoder / Screen

| Command | Description | Notes |
|---------|-------------|-------|
| `CD0` | CW screen display ON/OFF | Show/hide CW decode screen |
| `CD1` | CW decoding threshold | Sensitivity 001–030 |
| `CD2` | Decoded character output | Answer-only: pushes decoded chars via AI |
| `CD3` | CW decode filter | Pre-decode filter setting |
| `CD4` | CW screen quick mode | Fast-decode mode |
| `CD5` | CW decode ON/OFF | Master switch for CW decoder |

---

## Tier 1 — High Value: Missing VOX Controls

The app has `VX` (VOX on/off) but none of the VOX tuning parameters.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `VD` | VOX Delay Time | `VDP1P1P1P1;` 0000–2000 ms | How long after voice stops before TX→RX. |
| `VG0` | VOX Gain | `VG0P1P1P1;` 000–100 | Mic sensitivity to trigger VOX. |
| `VG1` | Anti-VOX Level | `VG1P1P1P1;` 000–100 | Speaker rejection to prevent VOX self-trigger. |

---

## Tier 1 — High Value: Meters

The app reads `SM;` (S-meter/power). The RM command gives access to all individual meters.

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `RM` | All meter readings | `RMP1P2P3;` P1=meter type (1–8) | Returns current, voltage, SWR, ALC, compression, power, etc. |
| `MT` | Meter selection (display) | `MTP1P2;` | Choose which meter is shown on radio display. |

---

## Tier 2 — Useful: Antenna Selection

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `AN` | Antenna Selection | `ANP1P2P3P4;` P1=0–9 | Select TX/RX antenna (ANT1/2/3 + RX antenna). |
| `AM` | Auto Mode (frequency-based) | `AMP1;` P1=0/1 | Auto-select mode by frequency. |

---

## Tier 2 — Useful: Memory Operations (extended)

The app has MA0–MA2. Missing:

| Command | Description | Notes |
|---------|-------------|-------|
| `MI` | Write VFO → Memory | Copy current VFO to a memory channel |
| `MA3` | Memory scan lockout | Mark channels to skip during scan |
| `MA4` | Memory channel copy | Duplicate one channel to another |
| `MA5` | Memory channel delete | Erase a channel |
| `MA6` | Programmable VFO end frequency | Set upper bound for VFO scan range |
| `MA7` | Memory channel temp freq change | Temporarily tune a channel without overwriting it |

---

## Tier 2 — Useful: Quick Memory

| Command | Description | Notes |
|---------|-------------|-------|
| `QI` | Write current frequency to Quick Memory | Like hitting the QM-IN button |
| `QA` | Quick Memory channel info (read) | Returns freq/mode for a QM channel |
| `QR` | Quick Memory ON/OFF | Switch to/from quick memory |
| `QD` | Delete all Quick Memory channels | Clear all QM slots |

---

## Tier 2 — Useful: Scanning (extended)

The app has SC0 (scan start/stop). Missing:

| Command | Description | Notes |
|---------|-------------|-------|
| `SC1` | Scan speed | 1–9 (slow to fast) |
| `SC2` | Tone scan / CTCSS scan | Scan for matching CTCSS tones |
| `SC3` | Program/VFO scan selection | Choose scan type |
| `SS` | Program scan slow-scan point frequency | Mark frequencies for slow-scan |
| `SU` | Program scan section / memory scan group | Configure scan groups |

---

## Tier 2 — Useful: FM / Tone (for repeater use)

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `CN` | CTCSS Frequency | `CNP1P1;` 00–42 | CTCSS tone number (00=off). |
| `TN` | FM Tone Frequency | `TNP1P1;` 00–42 | TX tone for FM repeater access. |
| `TO` | Tone / CTCSS / Cross Tone | `TOP1;` P1=0/1/2/3 | Tone type (off/tone/CTCSS/cross). |

---

## Tier 2 — Useful: Linear Amplifier Control

The TS-890S has a dedicated linear amplifier port (ACC4) with full relay/ALC control.

| Command | Description | Notes |
|---------|-------------|-------|
| `LA0` | Target band for linear amp menu | Select which band's settings to edit |
| `LA1` | Linear amp ON/OFF per band | Enable/disable amp for each band |
| `LA2` | Linear amp TX control | Who controls PTT: radio or amp |
| `LA3` | TX delay ON/OFF | Enable tx delay for amp warm-up |
| `LA4` | TX delay time | Delay in ms (0–9999) |
| `LA5` | Linear amp relay control | Relay close timing |
| `LA6` | External ALC voltage (read) | Read back ALC voltage from amp |

---

## Tier 2 — Useful: TX Power Limiter

| Command | Description | Notes |
|---------|-------------|-------|
| `LP0` | Read current power limiter level | Returns current limit in watts |
| `LP1` | Configure power limiter per band | Set max power per band |
| `LP2` | Power limiter ON/OFF | Enable/disable the limiter |

---

## Tier 2 — Useful: Recording

| Command | Description | Notes |
|---------|-------------|-------|
| `RE` | Recording function | Start/stop/playback radio recording |

---

## Tier 2 — Useful: Voice Message Playback (8 channels)

| Command | Description |
|---------|-------------|
| `LM` | Start/stop voice message recording |
| `PB0` | Voice message list display ON/OFF |
| `PB1` | Voice message playback (channel, start/stop) |
| `PB2` | Voice message registration state (read) |
| `PB3` | Voice message channel repeat |
| `PB4` | Voice message channel name |
| `PB5` | Recording sound source selection |
| `PB6` | Recording remaining time (read) |

---

## Tier 2 — Useful: Split / TF-SET

| Command | Description | Format | Notes |
|---------|-------------|--------|-------|
| `TB` | Split ON/OFF (direct) | `TBP1;` P1=0/1 | Simpler split toggle than SP. |
| `TS` | TF-SET (TX=VFO B, RX=VFO A) | `TSP1;` P1=0/1 | Enables transmit-frequency set mode. |

---

## Tier 3 — Lower Priority / Niche

### Clock (extended)

The app has CK0, CK2, CK8. Missing:

| Command | Description |
|---------|-------------|
| `CK1` | Clock setting state (is it set?) |
| `CK3` | Secondary clock time zone |
| `CK4` | Secondary clock identifier character (A-Z) |
| `CK5` | Date format (YY/MM/DD, DD/MM/YY, MM/DD/YY) |
| `CK6` | Automatic NTP date/time retrieval ON/OFF |
| `CK7` | NTP server address |
| `CK9` | Clock display type |

### Display / Dimmer / Screen

| Command | Description |
|---------|-------------|
| `DM0` | Dimmer level (1–4) |
| `DM1` | Dimmer preset adjustment |
| `DS0` | Basic screen display state |
| `DS1` | Function screen display state |
| `DS2` | Other screen display state |
| `DS3` | Close function setting screen |

### Frequency Markers (visual on bandscope)

| Command | Description |
|---------|-------------|
| `FM0` | Frequency marker function ON/OFF |
| `FM1` | Register frequency marker |
| `FM2` | Total registered markers (read) |
| `FM3` | Frequency marker list readout |
| `FM4` | Delete frequency marker |

### ΔF Display

| Command | Description |
|---------|-------------|
| `DF` | ΔF (delta-F) display: show offset from reference frequency |

### Timers / Scheduler

| Command | Description |
|---------|-------------|
| `TM0` | Timer ON/OFF |
| `TM1` | Program timer (schedule TX/RX) |
| `TM2` | Sleep timer |

### Transverter

| Command | Description |
|---------|-------------|
| `XO` | Transverter oscillating frequency (LO offset) |
| `XV` | Transverter function ON/OFF |

### Voice Guide (accessibility feature — radio built-in TTS)

| Command | Description |
|---------|-------------|
| `VR0` | Voice guide ON/OFF + volume + speed |
| `VR1` | Auto announce pause |

### Miscellaneous

| Command | Description |
|---------|-------------|
| `SR` | Reset (soft reset radio) |
| `TI` | Temporary TX inhibit |
| `BK` | Blanking of received signal |
| `BY` | BUSY LED state (read) |
| `CG` | Carrier level (000–100) |
| `CH` | MULTI/CH control |
| `CP` | Internal memory / USB remaining (read) |
| `MF` | Operation environment configuration |
| `MK` | Mode key operation (simulate pressing mode button) |
| `ME0/ME1` | Pop-up message display |
| `EQR2` | RX EQ copy (copy preset A/B/custom) |
| `EQT2` | TX EQ copy |

---

## Tier 3 — Bandscope Extended Controls

The app uses BS4 (span) and DD0/DD1 (scope data output). The following bandscope commands are all unimplemented:

| Command | Description |
|---------|-------------|
| `BS0` | Scope display ON/OFF |
| `BS1` | Scope display type (bandscope / audio scope / oscilloscope) |
| `BS3` | Bandscope operation mode (centre / fixed / scroll) |
| `BS5` | Fixed-mode scope range (0–3) |
| `BS6` | Display pause |
| `BS7` | Marker |
| `BS8` | Bandscope attenuator (0–3) |
| `BS9` | Max hold ON/OFF |
| `BSA` | Display averaging (0–3) |
| `BSB` | Waterfall display speed (1–4) |
| `BSC` | Reference level (000–060 dB) |
| `BSD` | Waterfall display clear |
| `BSE` | Marker shift / marker centre |
| `BSG` | Audio scope attenuator |
| `BSH` | Audio scope span |
| `BSI` | Oscilloscope level |
| `BSJ` | Oscilloscope sweep time |
| `BSK` | Bandscope shift position |
| `BSL` | OVF display state (read) |
| `BSM` | Scope range lower/upper frequency limits |
| `BSN` | Audio scope display pause |
| `BSO` | Expanded spectrum analysis range |

Also not yet handling the answer-only bandscope data commands:

| Command | Description |
|---------|-------------|
| `DD3` | Filter scope display information (AI-pushed) |
| `DD4` | Bandscope display information (non-AI version) |

---

## Network / IP (Tier 3)

The app handles KNS session management but not IP configuration from CAT.

| Command | Description |
|---------|-------------|
| `IP0` | DHCP ON/OFF |
| `IP1` | Manual IP address, subnet, gateway, DNS |
| `IP2` | MAC address (read) |

---

## Recommended Implementation Order

Based on user impact:

1. **`EC`, `VV`** — VFO swap / copy (2 commands, huge daily use)
2. **`LK`, `MU`, `QS`, `PS`** — Lock, mute, speaker mute, power (4 commands)
3. **`PT`, `SD`, `CA`** — CW pitch, break-in delay, auto-tune (3 commands, CW ops)
4. **`NB2` + `NL1`, `NL2`, `NBT`, `NBD`, `NBW`** — Full NB2 support (6 commands)
5. **`BP`, `NW`** — Notch position + bandwidth (2 commands)
6. **`RL1`, `RL2`** — NR level tuning (2 commands)
7. **`AP0–AP3`** — Audio Peak Filter / APF (4 commands, CW ops)
8. **`GT`, `AQ0`, `AQ1`** — AGC presets + quick recovery (3 commands)
9. **`FL1`, `FL2`, `FL3`** — Roofing filter, IF shape, AF type (3 commands)
10. **`PL`, `PR1`** — Speech processor levels + type (2 commands)
11. **`DV`, `VD`, `VG0`, `VG1`** — DATA VOX + VOX params (4 commands)
12. **`MO0`, `MO1`, `MO2`** — Monitor ON/OFF (3 commands)
13. **`RM`, `MT`** — Full meter access (2 commands)
14. **`AN`, `FW`** — Antenna selection, FM filter width (2 commands)
15. **`MO0-MO2`, `FV`, `BD/BU`, `FS`, `UD`** — Misc useful controls
16. Tier 2: Memory extensions, scanning, FM tone, linear amp, recording
17. Tier 3: Bandscope extended controls, timers, transverter, display

---

## Commands in App Not in Reference

| Command | Status | Notes |
|---------|--------|-------|
| `DA` | Legacy | No DA command in TS-890S reference. Kept for parser compatibility. |
| `MD` | Legacy | Legacy TS-2000 mode command. Not in TS-890S reference. Kept for parser compat. |

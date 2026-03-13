# TS-890 Pro — CAT Command Audit

**Purpose:** Verify every CAT command string used in the app against the PC Command Reference (`ts-890-computer-control90_pc_command_en_rev1.md`).

**Reference path:** `/Users/justinmann/Downloads/ts-890-computer-control90_pc_command_en_rev1.md`

**Status key:**
- `pending` — not yet audited
- `ok` — verified correct
- `wrong` — format, parameters, or R/W direction mismatch — needs fix
- `missing` — command used in app but not found in reference
- `fixed` — was wrong, now corrected in code

**How to resume:** Find the first row that is not `ok` or `fixed` and start there.

---

## Audit Progress

### Batch 1: AC – DD (Session 1, 2026-03-12, Auditor: Opus 4.6)

| # | Command | App Usage | Source File | Status | Notes |
|---|---------|-----------|-------------|--------|-------|
| 1 | `AC` | Antenna tuner get/set | KenwoodCAT.swift:272-281 | ok | Ref: `ACP1P2P3;` P1=1(always), P2=TX 0/1, P3=0/1. All app variants verified correct. |
| 2 | `AG` | AF gain get/set (000-255) | KenwoodCAT.swift:49-54 | ok | Ref: `AGP1P1P1;` P1=000–255. Matches exactly. |
| 3 | `AI` | Auto information mode (0/2/4) | KenwoodCAT.swift:28-30, RadioState.swift:575,2981,3027,3040 | ok | Ref: `AIP1;` P1=0(off)/2(on non-persistent)/4(on persistent). App uses 0,2,4 — correct. |
| 4 | `BC` | Beat cancel (0=off,1=BC1,2=BC2) | KenwoodCAT.swift:505-506 | ok | Ref: `BCP1;` P1=0/1/2. Matches. |
| 5 | `BI` | CW break-in (0=off,1=on) | KenwoodCAT.swift:558-559 | ok | Ref: `BIP1;` P1=0/1. Matches. |
| 6 | `BS` | Bandscope span read (`BS4;`) | RadioState.swift:583 | ok | `BS4;` is the correct read command for BS4 (Bandscope Span). |
| 7 | `CK0` | Clock date+time get/set (`CK0YYMMDDHHMMSS;`) | KenwoodCAT.swift:637-653 | ok | Reference grid confirms P6=seconds (2 digits). App sends `CK0YYMMDDHHMMSS;` (12 data digits). Correct. |
| 8 | `CK2` | Local timezone (000-112) | KenwoodCAT.swift:646-650 | ok | Ref: `CK2P1P1P1;` 000–112, 056=UTC, step=15min. App formula `56 + (offsetMinutes/15)` is correct. |
| 9 | `CK8` | Trigger NTP sync | KenwoodCAT.swift:657 | ok | Ref: `CK8;` set only, no parameters. Correct. |
| 10 | `DA` | Data mode get/set (0/1) | KenwoodCAT.swift:141-142 | **missing** | **No `DA` command in the TS-890S PC Command Reference.** D-section has: DD0-4, DF, DM0/1, DN/UP, DS0-3, DV — no DA. May be unsupported or accessible only via EX menu. Needs investigation. |
| 11 | `DD` | Filter scope output (0=none,1=LAN,2=COM) | RadioState.swift:582,2984,3028,3041 | ok | Ref: `DD0P1;` P1=0(no output)/1(LAN high)/2(LAN mid)/3(LAN low)/4(COM AI-linked)/5(COM). App sends `DD00;` and `DD01;` — correct. |

### Batch 2: EQR – IS (Session 2, 2026-03-12, Auditor: Opus 4.6)

| # | Command | App Usage | Source File | Status | Notes |
|---|---------|-----------|-------------|--------|-------|
| 12 | `EQR` (read) | `getRXEQPreset()` = `EQR0;` | KenwoodCAT.swift:434 | **wrong** | `EQR0;` reads ON/OFF state, not preset. To read active preset, send `EQR1;`. |
| 12b | `EQR` (set) | `setRXEQPreset()` = `EQR1n;` n=0–8 | KenwoodCAT.swift:435 | **wrong** | Wire format `EQR1n;` is correct, but preset 5 is named `conventional` in app — reference calls EQR1 P1=5 **"Flat"** (TX side is "Conventional"; they differ). Semantic/display bug. |
| 13 | `EQT` (read) | `getTXEQPreset()` = `EQT0;` | KenwoodCAT.swift:432 | **wrong** | `EQT0;` reads ON/OFF state, not preset. To read active preset, send `EQT1;`. |
| 13b | `EQT` (set) | `setTXEQPreset()` = `EQT1n;` n=0–8 | KenwoodCAT.swift:433 | ok | Wire format correct; TX preset 5 = "Conventional" matches reference. |
| 14 | `EX` | Extended menu get/set | KenwoodCAT.swift:354-367, RadioState.swift:2992,2996 | ok | Format verified: `EXP1P2P2P3P3;` (read), `EXP1P2P2P3P3 P5P5P5;` (set). Matches reference exactly. |
| 15 | `FA` | VFO A frequency get/set (11-digit Hz) | KenwoodCAT.swift:12-19 | ok | Ref: 11-digit zero-padded Hz. App: `FA%011d;`. Correct. |
| 16 | `FB` | VFO B frequency get/set (11-digit Hz) | KenwoodCAT.swift:21-26 | ok | Same as FA. Correct. |
| 17 | `FL` (read) | `getFilterSlot()` = `FL0;` | KenwoodCAT.swift:488 | **wrong** | `FL0;` (no P1) is invalid. Ref read format: `FL0P1;` — P1 required (0=A,1=B,2=C). Must send `FL00;`/`FL01;`/`FL02;` to query each slot. |
| 17b | `FL` (set) | `setFilterSlot()` = `FL0n;` | KenwoodCAT.swift:489 | ok | `FL0P1;` with P1=0/1/2. Correct. |
| 18 | `FR` | Receiver VFO get/set (0=A,1=B) | KenwoodCAT.swift:208-209 | ok | Ref: `FRP1;` P1=0/1/3. App uses 0/1. Correct. |
| 19 | `FT` | Transmitter VFO get/set (0=A,1=B) | KenwoodCAT.swift:211-212 | ok | Ref: `FTP1;` P1=0/1. Correct. |
| 20 | `GC` | AGC get/set (0=off,1=slow,2=mid,3=fast) | KenwoodCAT.swift:447-448 | ok | Ref: `GCP1;` P1=0–4. App uses 0–3. Correct (P1=4 unused — acceptable). |
| 21 | `ID` | Radio model ID | RadioState.swift:936 | ok | Read-only `ID;` → `ID024;`. Correct. |
| 22 | `IS` | IF shift get/set (`IS±NNNN;`) | KenwoodCAT.swift:252-259 | ok | Ref: `ISP1P2P2P2P2;` (P1=sign, P2=4-digit Hz). App: `IS+NNNN;`/`IS-NNNN;`. Correct. |

### Batch 3: KS – NT (Session 3, 2026-03-12, Auditor: Opus 4.6)

| # | Command | App Usage | Source File | Status | Notes |
|---|---------|-----------|-------------|--------|-------|
| 23 | `KS` | CW key speed get/set (004-060 WPM) | KenwoodCAT.swift:540-545 | ok | Ref: `KSP1P1P1;` 004–060. Matches. |
| 24 | `KY` (send) | `KY text;` (space before text) | RadioState.swift:2828 | ok | Ref: P1=space or "2", P2=text. Space is valid. Correct. |
| 24b | `KY` (abort) | `KY0;` | RadioState.swift:2833 | ok | Ref: P1=0 stops sending. Correct. |
| 25 | `MA0` | `MA0nnn;` read channel config | KenwoodCAT.swift:312-315 | ok | Ref: `MA0P1P1P1;` 000–119. Matches. |
| 25b | `MA1` | `MA1` + 11-digit Hz + mode + fmNarrow + `;` | KenwoodCAT.swift:317-323 | ok | Format matches reference exactly. |
| 25c | `MA2` | `MA2nnn name;` padded to 10 chars | KenwoodCAT.swift:325-332 | ok | Reference says "up to 10 chars" — trailing space padding is acceptable. |
| 26 | `MD` | Mode get/set | KenwoodCAT.swift:134-135 | **missing** | **No `MD` command in TS-890S PC Command Reference.** `MD` is a legacy Kenwood command (TS-2000 etc.) not present in TS-890S. Radio will return `?;`. App should use `OM` for mode control. |
| 27 | `MG` | Mic gain get/set (`MG0nnn;`) | KenwoodCAT.swift:511-515 | **wrong** | Ref: `MGP1P1P1;` (3 digits, 000–100). App sends `MG0%03d;` = 4 digits (e.g. `MG0050;` for 50). Should be `MG050;`. Leading `0` is spurious. |
| 28 | `ML` | Monitor level get/set (000-020) | KenwoodCAT.swift:525-530 | ok | Ref: `MLP1P1P1;` 000–020. Matches. |
| 29 | `MN` | Memory channel number get/set (000-119) | KenwoodCAT.swift:305-309 | ok | Ref: `MNP1P1P1;` 000–119. Matches. |
| 30 | `MS` | TX audio source (`MS001;`/`MS002;`/`MS003;`) | KenwoodCAT.swift:117-128, RadioState.swift:multiple | **wrong** | Ref: `MSP1P2P3;` — P1=0(SEND/PTT)/1(DATA SEND), P2=0(Front OFF)/1(Mic), P3=0(OFF)/1(ACC2)/2(USB)/3(LAN). `MS001` = P1=0, P2=0, P3=1 = PTT, Front=OFF, Rear=ACC2 — **not microphone**. Microphone = `MS010;`. `MS002;`=USB correct, `MS003;`=LAN correct. Comments in app incorrectly label `MS001` as "Front=Microphone". |
| 31 | `MV` | Memory mode (`MV;;` / `MV0;;` / `MV1;;`) | KenwoodCAT.swift:298-303 | **wrong** | Ref: single `;` terminator (`MV;` read, `MVP1;` set). The `；;` in the reference is a PDF fullwidth+halfwidth artifact — not a real double semicolon. App must use `MV;`/`MV0;`/`MV1;`. |
| 32 | `NB` | Noise blanker (`NB;`/`NB0;`/`NB1;`) | KenwoodCAT.swift:493-494 | **wrong** | **No plain `NB` command in TS-890S reference.** Reference defines `NB1` and `NB2` as separate commands (`NB1P1;`, `NB2P1;`). App must use `NB1`/`NB2` not `NB`. |
| 33 | `NR` | Noise reduction get/set (0/1/2) | KenwoodCAT.swift:160-161 | ok | Ref: `NRP1;` P1=0/1/2. Matches. |
| 34 | `NT` | Notch get/set (0/1) | KenwoodCAT.swift:163-164 | ok | Ref: `NTP1;` P1=0/1. Matches. |

### Batch 4: OM – RX (Session 4, 2026-03-12, Auditor: Opus 4.6)

| # | Command | App Usage | Source File | Status | Notes |
|---|---------|-----------|-------------|--------|-------|
| 35 | `OM` (read) | `OM0;` or `OM1;` | KenwoodCAT.swift:100-102 | ok | Ref: `OMP1;` P1=0(left)/1(right). Correct. |
| 35b | `OM` (set) | `OM0%X;` (P1=0 placeholder, P2=hex mode) | KenwoodCAT.swift:104-108 | ok | Ref explicitly states P1 is ignored for set. Uppercase hex A–F confirmed. Mode 8 unused — app correctly omits it. |
| 36 | `PA` | Preamp get/set (0=off,1=pre1,2=pre2) | KenwoodCAT.swift:474-475 | ok | Ref: `PAP1;` P1=0/1/2. Matches. |
| 37 | `PC` | TX power get/set (005-100 W) | KenwoodCAT.swift:263-268 | ok* | Wire format `PC%03d;` (3-digit) correct. *Minor gap: app clamps 5–100 unconditionally; AM mode limits differ (025W HF, 013W 70MHz). Radio will reject — app doesn't pre-clamp by mode. Not a wire error. |
| 38 | `PR` (read) | `getSpeechProc()` = `PR;` | KenwoodCAT.swift:534 | **wrong** | No bare `PR` command. Reference command is `PR0` (ON/OFF) and `PR1` (Effect Type). Read must be `PR0;`. |
| 38b | `PR` (set) | `PR0;`=off, `PR1;`=on | KenwoodCAT.swift:535 | **wrong** | `PR0;` is a valid read of PR0 (not a set). `PR1;` is a read of PR1 (Effect Type — unrelated). Correct forms: `PR00;`=off, `PR01;`=on. |
| 39 | `RA` | Attenuator get/set (0-3) | KenwoodCAT.swift:460-463 | ok | Ref: `RAP1;` P1=0(off)/1(6dB)/2(12dB)/3(18dB). Matches. |
| 40 | `RC` | RIT/XIT clear offset | KenwoodCAT.swift:222 | ok | Ref: Set only, no parameters `RC;`. Correct. |
| 41 | `RD` | Step down / set negative offset (`RD%05d;`) | KenwoodCAT.swift:225,233-235 | ok | Ref: `RD;` (step) and `RDP1P1P1P1P1;` (5-digit set). Both correct. |
| 42 | `RF` | RIT/XIT offset read | KenwoodCAT.swift:223 | ok | Ref: `RF;` read-only → `RFP1P2P2P2P2;` (direction + 4-digit Hz). Correct. |
| 43 | `RG` | RF gain get/set (000-255) | KenwoodCAT.swift:179-185 | ok | Ref: `RGP1P1P1;` 000–255. Matches. |
| 44 | `RT` | RIT state get/set (0/1) | KenwoodCAT.swift:216-217 | ok | Ref: `RTP1;` P1=0/1. Correct. (RT = RIT only; XIT is XT — naming note, not a bug.) |
| 45 | `RU` | Step up / set positive offset (`RU%05d;`) | KenwoodCAT.swift:225,231-232 | ok | Ref: `RU;` (step) and `RUP1P1P1P1P1;` (5-digit set). Both correct. |
| 46 | `RX` | PTT off | KenwoodCAT.swift:196-197 | ok | Ref: Set only, no parameters `RX;`. Correct. |

### Batch 5: SC – XT (Session 5, 2026-03-12, Auditor: Opus 4.6)

| # | Command | App Usage | Source File | Status | Notes |
|---|---------|-----------|-------------|--------|-------|
| 47 | `SC` | Scan start/stop (`SC1;` / `SC0;`) | RadioState.swift:1084,1090 | **wrong** | **`SC` is not a command.** `SC0` is the scan on/off command. `SC0;` (no P1) = Read current state. `SC1;` = Read scan speed. Correct: `SC01;` to start scan, `SC00;` to stop. |
| 48 | `SH` | Filter high cut setting ID (`SH0nnn;`) | KenwoodCAT.swift:246-250 | ok | Ref: `SHP1P2P2P2;` P1=0(setting)/1(preset), P2=000–999. `SH0;` (read P1=0) and `SH0nnn;` (set) correct — leading `0` is P1. |
| 49 | `SL` | Filter low cut setting ID (`SL0nn;`) | KenwoodCAT.swift:240-244 | ok | Ref: `SLP1P2P2;` P1=0(setting)/1(preset), P2=00–99. `SL0;` and `SL0nn;` correct — leading `0` is P1. |
| 50 | `SM` | Meter read (`SM0;`/`SM1;`/`SM2;`/`SM3;`/`SM5;`) | KenwoodCAT.swift:624-627 | **wrong** | **No indexed SM command in TS-890S reference.** `SM` is a single no-parameter read: `SM;` only. Returns 4-digit dot count (0000–0070). S-meter during RX, power during TX. All `SM0;`–`SM5;` sends are malformed. |
| 51 | `SP` | Split offset state/set | KenwoodCAT.swift:285-294 | ok | All four forms verified: `SP;`(read), `SP1;`(start), `SP2;`(cancel), `SP0dn;`(set dir+kHz). All match reference. |
| 52 | `SQ` | Squelch get/set (000-255) | KenwoodCAT.swift:168-173 | ok | Ref: `SQP1P1P1;` 000–255. Matches. |
| 53 | `TF` | Transverter filter read (`TF1;`/`TF2;`) | RadioState.swift:950,951 | ok | `TF1` and `TF2` are 3-char read-only command names. App sends both as reads on connect. Correct. |
| 54 | `TX` | PTT on (`TX0;`) | KenwoodCAT.swift:189-191 | ok | Ref: `TXP1;` P1=0(SEND/PTT). `TX0;` correct. |
| 55 | `UR` | RX EQ bands get/set (18 × 2-digit raw) | KenwoodCAT.swift:429-430 | ok | Ref: 18 bands × 2-digit raw 00–30. App encoding `raw = 6 − dB` verified correct (00=+6dB, 06=0dB, 30=−24dB). |
| 56 | `UT` | TX EQ bands get/set (18 × 2-digit raw) | KenwoodCAT.swift:427-428 | ok | Same structure as UR. Verified correct. |
| 57 | `VX` | VOX get/set (0/1) | KenwoodCAT.swift:519-520 | ok | Ref: `VXP1;` P1=0/1. Matches. |
| 58 | `XT` | XIT state get/set (0/1) | KenwoodCAT.swift:219-220 | ok | Ref: `XTP1;` P1=0/1. Matches. |

### Batch 6: KNS Commands (Session ?, Auditor: ?)

*Note: KNS commands (`##`) are Kenwood Network Server protocol, not in the standard PC Command Reference. Verify against KNS documentation or empirical testing only.*

| # | Command | App Usage | Source File | Status | Notes |
|---|---------|-----------|-------------|--------|-------|
| 59 | `##KN30` | VoIP input level get/set (000-100) | KenwoodCAT.swift:34-44 | pending | KNS protocol — not in PC cmd ref |
| 60 | `##KN31` | VoIP output level get/set (000-100) | KenwoodCAT.swift:34-44 | pending | KNS protocol — not in PC cmd ref |
| 61 | `##VP0` | Stop KNS VoIP audio stream | RadioState.swift:1609 | pending | KNS protocol — not in PC cmd ref |
| 62 | `##VP1` | Start KNS VoIP audio stream | RadioState.swift:564,1601,2356 | pending | KNS protocol — not in PC cmd ref |

---

## Session Log

| Session | Date | Batches Audited | Issues Found | Fixed |
|---------|------|-----------------|--------------|-------|
| 1 (extraction) | 2026-03-12 | — | — | — |
| 2 | 2026-03-12 | Batch 1 (AC–DD) | DA missing from reference | pending |
| 3 | 2026-03-12 | Batch 2 (EQR–IS) | EQR/EQT read wrong cmd; EQR preset 5 label wrong; FL read missing P1 | pending |
| 4 | 2026-03-12 | Batch 3 (KS–NT) | MD missing; MG extra leading 0; MS001≠mic; MV double ;;; NB wrong command name | pending |
| 5 | 2026-03-12 | Batch 4 (OM–RX) | PR wrong (PR0/PR00/PR01); PC AM-mode gap (minor) | pending |
| 6 | 2026-03-12 | Batch 5 (SC–XT) | SC wrong (SC00/SC01); SM no indexed variant | pending |

---

## Master Issues List — All Findings This Audit

**To fix in Phase 3:** Start from top, fix each, mark `fixed` in the batch table above.

| Priority | Command | File | Issue | Correct Form |
|----------|---------|------|-------|--------------|
| CRITICAL | `SC` | RadioState.swift:1084,1090 | `SC0;`/`SC1;` are Read commands, not start/stop. `SC` is not a command name. | Stop: `SC00;` Start: `SC01;` — **FIXED** |
| CRITICAL | `SM` | KenwoodCAT.swift:624-627 | No indexed SM variant. `SM0;`–`SM5;` are all invalid. Only `SM;` exists (S-meter RX, power TX). | `SM;` only — **FIXED** |
| CRITICAL | `NB` | KenwoodCAT.swift:493-494 | No plain `NB` command. Commands are `NB1` and `NB2`. | `NB1;`/`NB1P1;` — **FIXED** (NB1 as primary) |
| CRITICAL | `MS` | RadioState.swift:multiple | `MS001;` ≠ microphone. P2=0=Front OFF, P2=1=Front Mic. Mic = `MS010;` not `MS001;`. | Mic: `MS010;`, USB: `MS002;` ✓, LAN: `MS003;` ✓ — **FIXED** |
| HIGH | `PR` | KenwoodCAT.swift:534-535 | No bare `PR`. `PR;`=invalid read, `PR1;`=reads Effect Type (wrong). Commands: `PR0` (on/off), `PR1` (effect). | Read: `PR0;` Off: `PR00;` On: `PR01;` — **FIXED** |
| HIGH | `EQR` read | KenwoodCAT.swift:434 | `EQR0;` reads ON/OFF state, not preset. | Read preset: `EQR1;` — **FIXED** |
| HIGH | `EQT` read | KenwoodCAT.swift:432 | `EQT0;` reads ON/OFF state, not preset. | Read preset: `EQT1;` — **FIXED** |
| HIGH | `FL` read | KenwoodCAT.swift:488 | `FL0;` missing P1. P1 required in read. | `FL00;` — **FIXED** |
| HIGH | `MV` | KenwoodCAT.swift:298-303 | `;;` double semicolon is wrong. PDF artifact. | `MV;` `MV0;` `MV1;` — **FIXED** |
| HIGH | `MG` | KenwoodCAT.swift:511-515 | 4-digit param (`MG0nnn;`) should be 3-digit. | `MG;` read, `MGnnn;` set (000–100) — **FIXED** |
| MEDIUM | `MD` | KenwoodCAT.swift:134-135 | No `MD` command in TS-890S reference. | Removed from queryTop5; functions kept for parser compat only — **FIXED** |
| MEDIUM | `DA` | KenwoodCAT.swift:141-142 | No `DA` command in TS-890S reference. | Removed from queryTop5; functions kept for parser compat only — **FIXED** |
| MEDIUM | `EQR` label | KenwoodCAT.swift (EQPreset enum) | `conventional=5` is wrong for RX — reference names it "Flat". TX side is correct. | Added `rxLabel` property returning "Flat" for preset 5 — **FIXED** |
| LOW | `PC` | KenwoodCAT.swift:264-268 | AM mode max power not pre-clamped (025W HF, 013W 70MHz). Radio rejects silently. | No wire error; deferred — no change |

---

## Known Issues (pre-existing, from prior sessions)

| Command | Issue | Status |
|---------|-------|--------|
| `CK3` | Was wrong in earlier code — secondary timezone, not time set | Fixed before this audit |
| `CK4` | Was wrong — secondary identifier (A-Z), not timezone | Fixed before this audit |
| `CK5` | Was misidentified as something else | Fixed before this audit |

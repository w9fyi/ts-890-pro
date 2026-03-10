// TS890MenuDefinitions.swift
//
// EX command parameter mapping, confirmed against live radio scan (March 2026).
// EX number encoding: menuNumber = P2*100 + P3  (P1=0 regular menu)
//                     menuNumber = 10000 + P3    (P1=1 advanced menu)
//
// Items not found in EX scan (Clock menu, LAN/network settings) are excluded —
// those settings are panel-only and not accessible via PC control EX commands.
//
// EQ is NOT an EX menu item. Use EQT0/EQT1/EQR0/EQR1/UT/UR commands instead.

import Foundation

public struct TS890MenuItem: Identifiable {
    public let id = UUID()
    public let group: String
    public let number: Int
    public let displayLabel: String
    public let detail: String
}

public let ts890MenuItems: [TS890MenuItem] = [

    // MARK: - BASIC CONFIGURATION MENU (P2=00, items 0-32)

    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 0,   displayLabel: "Color Display Pattern",                        detail: "Display color type. Type 1 / Type 2 / Type 3. Default: Type 1."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 1,   displayLabel: "Function Key Style",                           detail: "Type of function key display. Type 1 / Type 2 / Type 3. Default: Type 1."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 2,   displayLabel: "Font Style (Frequency Display)",               detail: "Font type for frequency display. Font 1-5. Default: Font 1."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 3,   displayLabel: "Screen Saver",                                 detail: "Screen saver. Off / Type 1 / Type 2 / Type 3 / Display Off. Default: Off."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 4,   displayLabel: "Screen Saver Wait Time",                      detail: "Wait time before screen saver. Preview 5s / 5 / 15 / 30 / 60 min. Default: Preview."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 5,   displayLabel: "Screen Saver Message",                        detail: "Screen saver message text. Up to 10 alphanumeric characters."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 6,   displayLabel: "Power-on Message",                            detail: "Power-on message text. Up to 15 alphanumeric characters."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 7,   displayLabel: "FM Mode S-Meter Sensitivity",                 detail: "FM S-meter sensitivity. Normal / High. Default: Normal."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 8,   displayLabel: "Meter Response Speed (Analog)",               detail: "Analog meter response speed. 1 to 4. Default: 3."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 9,   displayLabel: "Meter Display Pattern",                       detail: "Meter type. Digital / Analog (White) / Analog (Black). Default: Analog (White)."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 10,  displayLabel: "Meter Display Peak Hold",                     detail: "Meter peak hold. Off / On. Default: On."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 11,  displayLabel: "S-Meter Scale",                               detail: "S-meter scale. Type 1 / Type 2. Default: Type 1."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 12,  displayLabel: "TX Digital Meter",                            detail: "TX meter (digital). Off / On. Default: Off."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 13,  displayLabel: "Long Press Duration of Panel Keys",           detail: "Duration for pressing and holding a key. 200-2000 ms (100 ms steps). Default: 500 ms."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 14,  displayLabel: "Touchscreen Tuning",                          detail: "Touchscreen tuning. Off / On. Default: On."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 15,  displayLabel: "PF A: Key Assignment",                        detail: "Function assignment for PF A key. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 16,  displayLabel: "PF B: Key Assignment",                        detail: "Function assignment for PF B key. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 17,  displayLabel: "PF C: Key Assignment",                        detail: "Function assignment for PF C key. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 18,  displayLabel: "External PF 1: Key Assignment",               detail: "Function assignment for PF 1 on keypad. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 19,  displayLabel: "External PF 2: Key Assignment",               detail: "Function assignment for PF 2 on keypad. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 20,  displayLabel: "External PF 3: Key Assignment",               detail: "Function assignment for PF 3 on keypad. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 21,  displayLabel: "External PF 4: Key Assignment",               detail: "Function assignment for PF 4 on keypad. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 22,  displayLabel: "External PF 5: Key Assignment",               detail: "Function assignment for PF 5 on keypad. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 23,  displayLabel: "External PF 6: Key Assignment",               detail: "Function assignment for PF 6 on keypad. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 24,  displayLabel: "External PF 7: Key Assignment",               detail: "Function assignment for PF 7 on keypad. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 25,  displayLabel: "External PF 8: Key Assignment",               detail: "Function assignment for PF 8 on keypad. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 26,  displayLabel: "Microphone PF 1: Key Assignment",             detail: "Function assignment for PF 1 on microphone. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 27,  displayLabel: "Microphone PF 2: Key Assignment",             detail: "Function assignment for PF 2 on microphone. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 28,  displayLabel: "Microphone PF 3: Key Assignment",             detail: "Function assignment for PF 3 on microphone. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 29,  displayLabel: "Microphone PF 4: Key Assignment",             detail: "Function assignment for PF 4 on microphone. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 30,  displayLabel: "Microphone DOWN: Key Assignment",             detail: "Function assignment for DOWN on microphone. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 31,  displayLabel: "Microphone UP: Key Assignment",               detail: "Function assignment for UP on microphone. Refer to PF key assignment ID list."),
    TS890MenuItem(group: "BASIC CONFIGURATION MENU", number: 32,  displayLabel: "Automatic Power Off",                         detail: "APO. Off / 60 / 120 / 180 min. Default: Off."),

    // MARK: - AUDIO PERFORMANCE MENU (P2=01, items 100-106)

    TS890MenuItem(group: "AUDIO PERFORMANCE MENU", number: 100, displayLabel: "Beep Volume",                                    detail: "Volume of beep tone. Off / 1-20. Default: 10."),
    TS890MenuItem(group: "AUDIO PERFORMANCE MENU", number: 101, displayLabel: "Voice Message Volume (Play)",                    detail: "Playback volume of voice message. Off / 1-20. Default: 10."),
    TS890MenuItem(group: "AUDIO PERFORMANCE MENU", number: 102, displayLabel: "Sidetone Volume",                                detail: "Sidetone volume. Off / 1-20 (linked with monitor control). Default: 10."),
    TS890MenuItem(group: "AUDIO PERFORMANCE MENU", number: 103, displayLabel: "Voice Guidance Volume",                         detail: "Voice guide volume. Off / 1-20. Default: 10."),
    TS890MenuItem(group: "AUDIO PERFORMANCE MENU", number: 104, displayLabel: "Voice Guidance Speed",                          detail: "Voice guide speed. 1 to 4. Default: 1."),
    TS890MenuItem(group: "AUDIO PERFORMANCE MENU", number: 105, displayLabel: "User Interface Language",                       detail: "Language for voice guidance and messages. English / Japanese. Default: English."),
    TS890MenuItem(group: "AUDIO PERFORMANCE MENU", number: 106, displayLabel: "Automatic Voice Guidance",                      detail: "Automatic voice guide. Off / On. Default: Off."),

    // MARK: - DECODING AND ENCODING MENU (P2=02, items 200-217)

    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 200, displayLabel: "FFT Scope Averaging (RTTY Decode)",          detail: "Averaging on FFT scope for RTTY decode. 0-9. Default: 0."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 201, displayLabel: "RX UOS",                                    detail: "RX unshift-on-space. Off / On. Default: On."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 202, displayLabel: "New Line Code",                             detail: "New line code during reception. CR+LF / All. Default: All."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 203, displayLabel: "Diddle",                                    detail: "Diddle. Off / Blank Code / Letters Code. Default: Blank Code."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 204, displayLabel: "TX UOS",                                    detail: "TX unshift-on-space. Off / On. Default: On."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 205, displayLabel: "Automatic Newline Insertion",               detail: "Automatic new line code insertion. Off / On. Default: On."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 206, displayLabel: "FSK Spacing",                               detail: "FSK shift width. 170 / 200 / 425 / 850 Hz. Default: 170 Hz."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 207, displayLabel: "FSK Keying Polarity",                       detail: "FSK keying polarity. Off / On. Default: Off."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 208, displayLabel: "FSK Tone Frequency",                        detail: "FSK tone frequency. 1275 / 2125 Hz. Default: 2125 Hz."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 209, displayLabel: "RTTY Tuning Scope",                         detail: "Scope display for FSK tuning. FFT Scope / X-Y Scope. Default: FFT Scope."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 210, displayLabel: "FFT Scope Averaging (PSK Decode)",          detail: "Averaging on FFT scope for PSK decode. 0-9. Default: 0."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 211, displayLabel: "PSK AFC Tuning Range",                      detail: "Tuning range for PSK AFC. plus or minus 8 / plus or minus 15 Hz. Default: plus or minus 15 Hz."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 212, displayLabel: "PSK Tone Frequency",                        detail: "PSK tone frequency. 1.0 / 1.5 / 2.0 kHz. Default: 1.5 kHz."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 213, displayLabel: "PSK Tuning Scope",                          detail: "Scope display for PSK tuning. FFT Scope / Vector Scope. Default: FFT Scope."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 214, displayLabel: "CW/RTTY/PSK Log File Format",               detail: "File format for CW/RTTY/PSK logs. html / txt. Default: txt."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 215, displayLabel: "CW/RTTY/PSK Time Stamp",                    detail: "Time stamp for logs. Off / Time Stamp / Stamp + Frequency. Default: Time Stamp."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 216, displayLabel: "Clock (CW/RTTY/PSK Time Stamp)",            detail: "Clock for log time stamp. Local Clock / Secondary Clock. Default: Local Clock."),
    TS890MenuItem(group: "DECODING AND ENCODING MENU", number: 217, displayLabel: "Waterfall when Tuning (RTTY/PSK Audio Scope)", detail: "RTTY/PSK waterfall display during tuning. Straight / Follow. Default: Straight."),

    // MARK: - CONTROLS AND CONFIGURATION MENU (P2=03, items 300-313)

    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 300, displayLabel: "Frequency Rounding Off (Multi/Channel Control)", detail: "Rounds frequency to step size. Off / On. Default: On."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 301, displayLabel: "SSB Mode Frequency Step Size",         detail: "SSB frequency step (Multi/CH). 0.5 / 1 / 2.5 / 5 / 10 kHz. Default: 1 kHz."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 302, displayLabel: "CW/FSK/PSK Mode Frequency Step Size",  detail: "CW/FSK/PSK frequency step (Multi/CH). 0.5 / 1 / 2.5 / 5 / 10 kHz. Default: 0.5 kHz."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 303, displayLabel: "FM Mode Frequency Step Size",          detail: "FM frequency step (Multi/CH). 5-100 kHz. Default: 10 kHz."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 304, displayLabel: "AM Mode Frequency Step Size",          detail: "AM frequency step (Multi/CH). 5-100 kHz. Default: 5 kHz."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 305, displayLabel: "9 kHz Step in AM Broadcast Band",      detail: "9 kHz step for AM broadcast band (Multi/CH). Off / On. Default: Off (K type)."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 306, displayLabel: "MHz Step",                             detail: "MHz step size. 100 / 500 / 1000 kHz. Default: 1000 kHz."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 307, displayLabel: "Tuning Control: Steps per Revolution", detail: "Steps per revolution of tuning control. 250 / 500 / 1000. Default: 1000."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 308, displayLabel: "Tuning Speed Control",                 detail: "Fast forward rate of tuning control. Off / 2-10. Default: Off."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 309, displayLabel: "Tuning Speed Control Sensitivity",     detail: "Sensitivity for fast forward. 1-10. Default: 5."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 310, displayLabel: "Lock Function",                        detail: "Frequency lock function. Frequency Lock / Tuning Control Lock. Default: Frequency Lock."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 311, displayLabel: "Number of Band Memories",              detail: "Band memories per band. 1 / 3 / 5. Default: 3."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 312, displayLabel: "Split Frequency Offset by RIT/XIT",    detail: "Changing split freq via RIT/XIT. Off / TX Freq Offset / RX Freq Offset / Both. Default: Off."),
    TS890MenuItem(group: "CONTROLS AND CONFIGURATION MENU", number: 313, displayLabel: "Band Direct Keys in Split Mode",       detail: "Band direct key during split. RX Band / RX Band + Cancel Split / RX/TX Band. Default: RX Band."),

    // MARK: - MEMORY CHANNELS AND SCANNING MENU (P2=04, items 400-405)

    TS890MenuItem(group: "MEMORY CHANNELS AND SCANNING MENU", number: 400, displayLabel: "Number of Quick Memory Channels",    detail: "Number of quick memory channels. 3 / 5 / 10. Default: 5."),
    TS890MenuItem(group: "MEMORY CHANNELS AND SCANNING MENU", number: 401, displayLabel: "Temporary Change (Memory Channel Configurations)", detail: "Temporary change of memory frequency. Off / On. Default: Off."),
    TS890MenuItem(group: "MEMORY CHANNELS AND SCANNING MENU", number: 402, displayLabel: "Program Slow Scan",                  detail: "Program slow scan. Off / On. Default: On."),
    TS890MenuItem(group: "MEMORY CHANNELS AND SCANNING MENU", number: 403, displayLabel: "Program Slow Scan Range",            detail: "Range of program slow scan. 100-500 Hz. Default: 300 Hz."),
    TS890MenuItem(group: "MEMORY CHANNELS AND SCANNING MENU", number: 404, displayLabel: "Scan Hold",                          detail: "Scan Hold. Off / On. Default: Off."),
    TS890MenuItem(group: "MEMORY CHANNELS AND SCANNING MENU", number: 405, displayLabel: "Scan Resume",                        detail: "Scan resume condition. Time-operated / Carrier-operated. Default: Time-operated."),

    // MARK: - CW CONFIGURATION MENU (P2=05, items 500-516)

    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 500, displayLabel: "Paddle Jack Configuration (Front)",              detail: "PADDLE jack function. Straight Key / Paddle / Paddle (Bug Key). Default: Paddle."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 501, displayLabel: "Key Jack Configuration (Rear)",                  detail: "KEY jack function. Straight Key / Paddle / Paddle (Bug Key). Default: Straight Key."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 502, displayLabel: "Electronic Keyer Squeeze Mode",                  detail: "Keyer squeeze mode. Mode A / Mode B. Default: Mode B."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 503, displayLabel: "Dot and Dash Reversed Keying",                   detail: "Swap dot/dash paddle. Off / On. Default: Off."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 504, displayLabel: "Paddle (Microphone Up/Down Keys)",               detail: "Use UP/DOWN mic keys as paddle. Off / On. Default: Off."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 505, displayLabel: "CW BFO Sideband",                                detail: "CW BFO sideband. USB / LSB. Default: USB."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 506, displayLabel: "Automatic CW TX with Keying in SSB Mode",        detail: "Auto switch to CW TX when keying in SSB mode. Off / On. Default: Off."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 507, displayLabel: "Carrier Frequency Offset",                       detail: "CW carrier frequency offset. Off / On. Default: Off."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 508, displayLabel: "CW Keying Weight Ratio",                         detail: "Keyer weight ratio. Automatic / 2.5-4.0 (0.1 steps). Default: Automatic."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 509, displayLabel: "CW Keying Reversed Weight Ratio",                detail: "Reverse keying auto weight ratio. Off / On. Default: Off."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 510, displayLabel: "Interrupt Keying",                               detail: "Insert keying. Off / On. Default: Off."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 511, displayLabel: "CW Message Entry",                               detail: "Method for registering CW message. Text String / Paddle. Default: Paddle."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 512, displayLabel: "Contest Number",                                  detail: "Contest number (4 digits). 0001-9999. Default: 001."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 513, displayLabel: "Contest Number Format",                          detail: "Contest number style. Off / 190 to ANO / 190 to ANT / 90 to NO / 90 to NT. Default: Off."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 514, displayLabel: "Channel Number (Count-up Message)",              detail: "Channel for count-up message. Off / Channel 1-8. Default: Off."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 515, displayLabel: "CW Rise Time",                                   detail: "CW rise time. 1 / 2 / 4 / 6 ms. Default: 4 ms."),
    TS890MenuItem(group: "CW CONFIGURATION MENU", number: 516, displayLabel: "CW/Voice Message Retransmit Interval Time",      detail: "Repeat interval for CW/voice message. 0-60 s. Default: 10 s."),

    // MARK: - TX AND AUDIO MENU (P2=06, items 600-615)

    TS890MenuItem(group: "TX AND AUDIO MENU", number: 600, displayLabel: "Playback Time (Full-time Recording)",                 detail: "Playback time for constantly recorded audio. Last 10 / 20 / 30 s. Default: Last 30 s."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 601, displayLabel: "Recording with Squelch",                             detail: "Audio recording in tandem with squelch. Off / On. Default: On."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 602, displayLabel: "Time-out Timer",                                     detail: "Maximum continuous TX time. Off / 3 / 5 / 10 / 20 / 30 min. Default: Off."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 603, displayLabel: "TX Inhibit",                                         detail: "Inhibits transmission. Off / On. Default: Off."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 604, displayLabel: "Transmit Power Step Size",                           detail: "Fine TX power adjustment step. 1 / 5 W. Default: 5 W."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 605, displayLabel: "ID Beep",                                            detail: "ID beep interval. Off / 1-30 min. Default: Off."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 606, displayLabel: "TX Filter Low Cut (SSB/AM)",                         detail: "TX filter low cutoff (SSB/AM). 10 / 100 / 200 / 300 / 400 / 500 Hz. Default: 100 Hz."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 607, displayLabel: "TX Filter High Cut (SSB/AM)",                        detail: "TX filter high cutoff (SSB/AM). 2500-4000 Hz. Default: 2900 Hz."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 608, displayLabel: "TX Filter Low Cut (SSB-DATA/AM-DATA)",               detail: "TX filter low cutoff (SSB-DATA/AM-DATA). 10-500 Hz. Default: 100 Hz."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 609, displayLabel: "TX Filter High Cut (SSB-DATA/AM-DATA)",              detail: "TX filter high cutoff (SSB-DATA/AM-DATA). 2500-4000 Hz. Default: 2900 Hz."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 610, displayLabel: "RX Filter Numbers",                                  detail: "Number of RX filters available. 2 / 3. Default: 3."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 611, displayLabel: "Filter Control in SSB Mode",                        detail: "High/Low Cut vs Shift/Width (SSB). High and Low Cut / Shift and Width. Default: High and Low Cut."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 612, displayLabel: "Filter Control in SSB-DATA Mode",                   detail: "High/Low Cut vs Shift/Width (SSB-DATA). High and Low Cut / Shift and Width. Default: Shift and Width."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 613, displayLabel: "VOX Voice Delay (Microphone)",                       detail: "Audio delay in VOX mode (MIC). Off / Short / Middle / Long. Default: Middle."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 614, displayLabel: "VOX Voice Delay (Except Microphone)",                detail: "Audio delay in VOX mode (excluding MIC). Off / Short / Middle / Long. Default: Middle."),
    TS890MenuItem(group: "TX AND AUDIO MENU", number: 615, displayLabel: "Delta Frequency Display",                            detail: "Delta-F display. Off / On. Default: On."),

    // MARK: - REAR CONNECTOR MENU (P2=07, items 700-711)

    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 700, displayLabel: "Baud Rate (COM Port)",                             detail: "COM connector baud rate. 4800 / 9600 / 19200 / 38400 / 57600 / 115200 bps. Default: 9600."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 701, displayLabel: "Baud Rate (Virtual Standard COM)",                 detail: "Virtual Standard COM baud rate. 9600-115200 bps. Default: 115200."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 702, displayLabel: "Baud Rate (Virtual Enhanced COM)",                 detail: "Virtual Enhanced COM baud rate. 9600-115200 bps. Default: 115200."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 703, displayLabel: "Decoded Character Output",                         detail: "Decoded character output. Off / On. Default: Off."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 704, displayLabel: "Quick Data Transfer",                              detail: "Quick data transfer. Off / A (TX/RX) / A (Sub RX) / B. Default: Off."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 705, displayLabel: "Overwrite Location (Quick Data Transfer)",         detail: "Destination for quick data transfer. VFO / Quick Memory. Default: Quick Memory."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 706, displayLabel: "USB: Audio Input Level",                           detail: "USB audio input level. 0-100. Default: 50."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 707, displayLabel: "ACC 2: Audio Input Level",                         detail: "ACC 2 audio input level. 0-100. Default: 50."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 708, displayLabel: "USB: Audio Output Level",                          detail: "USB audio output level. 0-100. Default: 100."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 709, displayLabel: "ACC 2: Audio Output Level",                        detail: "ACC 2 audio output level. 0-100. Default: 50."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 710, displayLabel: "TX Monitor Level (Rear Connectors)",               detail: "TX monitor level to rear panel connectors. Linked / 0-20. Default: Linked."),
    TS890MenuItem(group: "REAR CONNECTOR MENU", number: 711, displayLabel: "Audio Output Type (Rear Connectors)",              detail: "Audio output format from rear panel. All / Received Audio only. Default: All."),

    // MARK: - BANDSCOPE MENU (P2=08, items 800-807)

    TS890MenuItem(group: "BANDSCOPE MENU", number: 800, displayLabel: "Bandscope Display during TX",                           detail: "Bandscope display during transmission. Off / On. Default: Off."),
    TS890MenuItem(group: "BANDSCOPE MENU", number: 801, displayLabel: "TX Audio Waveform Display",                             detail: "Waveform display for transmitted audio. Off / On. Default: On."),
    TS890MenuItem(group: "BANDSCOPE MENU", number: 802, displayLabel: "Bandscope Maximum Hold",                                detail: "Maximum hold time. 10 s / Continuous. Default: 10 s."),
    TS890MenuItem(group: "BANDSCOPE MENU", number: 803, displayLabel: "Waterfall when Tuning (Center Mode)",                   detail: "Waterfall display during tuning (center mode). Straight / Follow. Default: Straight."),
    TS890MenuItem(group: "BANDSCOPE MENU", number: 804, displayLabel: "Waterfall Gradation Level",                             detail: "Waterfall gradation setting. 1-10. Default: 7."),
    TS890MenuItem(group: "BANDSCOPE MENU", number: 805, displayLabel: "Tuning Assist Line (SSB Mode)",                        detail: "Auxiliary tuning line (SSB only). Off / 300-2210 Hz. Default: Off."),
    TS890MenuItem(group: "BANDSCOPE MENU", number: 806, displayLabel: "Frequency Scale (Center Mode)",                         detail: "Frequency scale in center mode. Relative / Absolute. Default: Relative."),
    TS890MenuItem(group: "BANDSCOPE MENU", number: 807, displayLabel: "Automatic Correction Step (Touchscreen Tuning)",          detail: "Correction step for touchscreen tuning. 100 / 250 / 500 / 1000 Hz. Default: 100 Hz."),

    // MARK: - USB KEYBOARD MENU (P2=09, items 900-903)

    TS890MenuItem(group: "USB KEYBOARD MENU", number: 900, displayLabel: "Send Message by Function Keys",                      detail: "Function key settings of USB keyboard. Off / On. Default: On."),
    TS890MenuItem(group: "USB KEYBOARD MENU", number: 901, displayLabel: "Keyboard Language",                                  detail: "USB keyboard language. English / Other Languages. Default: English (US)."),
    TS890MenuItem(group: "USB KEYBOARD MENU", number: 902, displayLabel: "Repeat Delay Time",                                  detail: "Key repeat delay time for USB keyboard. 1-4. Default: 2."),
    TS890MenuItem(group: "USB KEYBOARD MENU", number: 903, displayLabel: "Repeat Speed",                                       detail: "Key repeat speed for USB keyboard. 1-32. Default: 1."),

    // MARK: - ADVANCED MENU (P1=1, items 10000-10027)
    // P2 is ignored for Advanced Menu. Number = 10000 + P3.
    // Items 10023-10026 are license/info screens with no corresponding command.

    TS890MenuItem(group: "ADVANCED MENU", number: 10000, displayLabel: "Indication Signal Type (External Meter 1)",            detail: "Signal type for external meter 1. Automatic / TX Power / ALC / Drain Voltage / COMP / Current / SWR. Default: Automatic."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10001, displayLabel: "Indication Signal Type (External Meter 2)",            detail: "Signal type for external meter 2. Automatic / TX Power / ALC / Drain Voltage / COMP / Current / SWR. Default: Automatic."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10002, displayLabel: "Output Level (External Meter 1)",                      detail: "Output level for external meter 1. 0-100%. Default: 50%."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10003, displayLabel: "Output Level (External Meter 2)",                      detail: "Output level for external meter 2. 0-100%. Default: 50%."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10004, displayLabel: "Reference Signal Source",                              detail: "Reference oscillator source. Internal / External. Default: Internal."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10005, displayLabel: "Reference Oscillator Calibration",                     detail: "Calibration offset. 0-1000 (corresponds to -500 to +500). Default: 500."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10006, displayLabel: "TX Power Down with Transverter Enabled",               detail: "Reduce TX power when transverter is enabled. Off / On. Default: On."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10007, displayLabel: "TX Hold After Antenna Tuning",                         detail: "Hold TX after antenna tuning. Off / On. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10008, displayLabel: "Antenna Tuner during RX",                              detail: "Antenna tuner active during RX. Off / On. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10009, displayLabel: "Antenna Tuner Operation per Band",                     detail: "Store tuner setting per band. Off / On. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10010, displayLabel: "Microphone Gain (FM Mode)",                            detail: "FM mode microphone gain. 0-100. Default: 50."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10011, displayLabel: "PKS Polarity Reverse",                                 detail: "PKS pin polarity reversal. Off / On. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10012, displayLabel: "TX Inhibit While Busy",                                detail: "Inhibit TX while channel is busy. Off / On. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10013, displayLabel: "CTCSS Unmute for Internal Speaker",                    detail: "CTCSS unmute for internal speaker. Mute / Unmute. Default: Mute."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10014, displayLabel: "PSQ Logic State",                                      detail: "PSQ pin logic state. Low / Open. Default: Low."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10015, displayLabel: "PSQ Reverse Condition",                                detail: "PSQ reverse condition. Off / Busy / Sql / Send / Busy-Send / Sql-Send. Default: value 2."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10016, displayLabel: "PSQ/PKS Pin Assignment (COM Connector)",               detail: "PSQ/PKS pin assignment on COM connector. Off / On. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10017, displayLabel: "Virtual Standard COM Port RTS",                        detail: "RTS function on virtual standard COM. Flow Control / CW Keying / RTTY Keying / PTT / DATA SEND. Default: Flow Control."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10018, displayLabel: "Virtual Standard COM Port DTR",                        detail: "DTR function on virtual standard COM. Off / CW Keying / RTTY Keying / PTT / DATA SEND. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10019, displayLabel: "Virtual Enhanced COM Port RTS",                        detail: "RTS function on virtual enhanced COM. Off / CW Keying / RTTY Keying / PTT / DATA SEND. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10020, displayLabel: "Virtual Enhanced COM Port DTR",                        detail: "DTR function on virtual enhanced COM. Off / CW Keying / RTTY Keying / PTT / DATA SEND. Default: Off."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10021, displayLabel: "External Display",                                     detail: "External display enable. Off / On. Default: On."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10022, displayLabel: "Resolution (External Display)",                        detail: "External display resolution. 800x600 / 848x480. Default: 800x600."),
    TS890MenuItem(group: "ADVANCED MENU", number: 10027, displayLabel: "Firmware Version",                                     detail: "Firmware version (read-only)."),
]

// TS990MenuDefinitions.swift
//
// EX command parameter mapping for TS-990S.
// The TS-990S uses the same P1/P2/P3 EX format as the TS-890S but with
// a different (and larger) set of menu items.
//
// Derived from the TS-990S PC Command Reference Rev. 2.
// This is a representative subset — a full menu scan (Settings → Discover)
// will populate any items not listed here.

import Foundation

let ts990MenuItems: [KenwoodMenuItem] = [

    // MARK: - BASIC CONFIGURATION (P2=00)

    KenwoodMenuItem(group: "BASIC CONFIGURATION", number: 0,   displayLabel: "Color Display Pattern",              detail: "Display color type. Type 1/2/3. Default: Type 1."),
    KenwoodMenuItem(group: "BASIC CONFIGURATION", number: 1,   displayLabel: "Font Style (Frequency Display)",     detail: "Frequency display font. Font 1-4. Default: Font 1."),
    KenwoodMenuItem(group: "BASIC CONFIGURATION", number: 2,   displayLabel: "Screen Saver",                       detail: "Screen saver. Off / Type 1/2/3 / Display Off. Default: Off."),
    KenwoodMenuItem(group: "BASIC CONFIGURATION", number: 3,   displayLabel: "Screen Saver Wait Time",             detail: "Screen saver delay. 5/15/30/60 min. Default: 60 min."),
    KenwoodMenuItem(group: "BASIC CONFIGURATION", number: 4,   displayLabel: "Power-on Message",                   detail: "Power-on message text. Up to 10 characters."),
    KenwoodMenuItem(group: "BASIC CONFIGURATION", number: 5,   displayLabel: "Long Press Duration",                detail: "Key long-press time. 200-2000 ms. Default: 500 ms."),
    KenwoodMenuItem(group: "BASIC CONFIGURATION", number: 6,   displayLabel: "Beep Volume",                        detail: "Beep volume. Off / 1-20. Default: 10."),
    KenwoodMenuItem(group: "BASIC CONFIGURATION", number: 7,   displayLabel: "Automatic Power Off",                detail: "APO. Off / 60/120/180 min. Default: Off."),

    // MARK: - TUNING CONTROLS (P2=01)

    KenwoodMenuItem(group: "TUNING CONTROLS", number: 100, displayLabel: "SSB Mode Frequency Step Size",           detail: "SSB tuning step. 0.5/1/2.5/5/10 kHz. Default: 1 kHz."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 101, displayLabel: "CW/FSK/PSK Mode Frequency Step",         detail: "CW/FSK/PSK tuning step. 0.5/1/2.5/5/10 kHz. Default: 0.5 kHz."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 102, displayLabel: "FM Mode Frequency Step Size",            detail: "FM tuning step. 5-100 kHz. Default: 10 kHz."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 103, displayLabel: "AM Mode Frequency Step Size",            detail: "AM tuning step. 5-100 kHz. Default: 5 kHz."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 104, displayLabel: "9 kHz Step in AM BC Band",               detail: "9 kHz step. Off / On. Default: Off."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 105, displayLabel: "MHz Step",                                detail: "MHz step. 100/500/1000 kHz. Default: 1000."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 106, displayLabel: "Tuning Control Steps per Rev",           detail: "Steps per revolution. 250/500/1000. Default: 1000."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 107, displayLabel: "Tuning Speed Control",                   detail: "Fast-forward rate. Off / 2-10. Default: Off."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 108, displayLabel: "Tuning Step Rounding",                   detail: "Frequency rounding. Off / On. Default: On."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 109, displayLabel: "Number of Band Memories",                detail: "Band memories per band. 1/3/5. Default: 3."),
    KenwoodMenuItem(group: "TUNING CONTROLS", number: 110, displayLabel: "Lock Function",                          detail: "Lock target. Frequency Lock / Tuning Control Lock. Default: Frequency Lock."),

    // MARK: - MEMORY AND SCAN (P2=02)

    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 200, displayLabel: "Quick Memory Channels",                  detail: "Number of quick memory channels. 3/5/10. Default: 5."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 201, displayLabel: "Memory Channel Temp Change",             detail: "Allow temporary memory change. Off / On. Default: Off."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 202, displayLabel: "Program Slow Scan",                      detail: "Program slow scan. Off / On. Default: On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 203, displayLabel: "Program Slow Scan Range",                detail: "Slow scan range. 100-500 Hz. Default: 300 Hz."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 204, displayLabel: "Scan Hold",                              detail: "Scan hold. Off / On. Default: Off."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 205, displayLabel: "Scan Resume",                            detail: "Scan resume method. Time / Carrier. Default: Time."),

    // MARK: - CW (P2=03)

    KenwoodMenuItem(group: "CW CONFIGURATION", number: 300, displayLabel: "Paddle Type (Front)",                   detail: "Front paddle function. Straight / Paddle / Bug. Default: Paddle."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 301, displayLabel: "Key Type (Rear)",                       detail: "Rear key function. Straight / Paddle / Bug. Default: Straight."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 302, displayLabel: "Keyer Squeeze Mode",                    detail: "A / B. Default: B."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 303, displayLabel: "Dot/Dash Reverse",                      detail: "Swap dot/dash. Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 304, displayLabel: "CW BFO Sideband",                       detail: "BFO sideband. USB / LSB. Default: USB."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 305, displayLabel: "Auto CW TX in SSB Mode",                detail: "Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 306, displayLabel: "CW Carrier Frequency Offset",           detail: "Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 307, displayLabel: "CW Weight",                             detail: "Auto / 2.5-4.0. Default: Auto."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 308, displayLabel: "CW Reversed Weight",                    detail: "Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 309, displayLabel: "CW Rise Time",                          detail: "1/2/4/6 ms. Default: 4 ms."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 310, displayLabel: "CW Message Repeat Interval",            detail: "0-60 s. Default: 10 s."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 311, displayLabel: "Contest Number",                         detail: "0001-9999. Default: 0001."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 312, displayLabel: "Contest Number Style",                   detail: "Off / ANO / ANT / NO / NT. Default: Off."),

    // MARK: - FSK/PSK (P2=04)

    KenwoodMenuItem(group: "FSK AND PSK", number: 400, displayLabel: "FSK Shift Width",                          detail: "170/200/425/850 Hz. Default: 170 Hz."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 401, displayLabel: "FSK Keying Polarity",                      detail: "Normal / Reverse. Default: Normal."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 402, displayLabel: "FSK Tone Frequency",                       detail: "1275/2125 Hz. Default: 2125 Hz."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 403, displayLabel: "TX UOS",                                   detail: "Off / On. Default: On."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 404, displayLabel: "Diddle",                                   detail: "Off / Blank / Letters. Default: Blank."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 405, displayLabel: "New Line Code",                            detail: "CR+LF / All. Default: All."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 406, displayLabel: "PSK Tone Frequency",                       detail: "1.0/1.5/2.0 kHz. Default: 1.5 kHz."),

    // MARK: - TX/RX (P2=05)

    KenwoodMenuItem(group: "TX AND RX", number: 500, displayLabel: "Time-out Timer",                             detail: "Off / 3/5/10/20/30 min. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 501, displayLabel: "TX Inhibit",                                 detail: "Off / On. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 502, displayLabel: "TX Power Step Size",                         detail: "1 / 5 W. Default: 5 W."),
    KenwoodMenuItem(group: "TX AND RX", number: 503, displayLabel: "ID Beep",                                    detail: "Off / 1-30 min. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 504, displayLabel: "TX Filter Low Cut (SSB/AM)",                 detail: "10-500 Hz. Default: 100 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 505, displayLabel: "TX Filter High Cut (SSB/AM)",                detail: "2500-4000 Hz. Default: 2900 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 506, displayLabel: "TX Filter Low Cut (SSB-DATA/AM-DATA)",       detail: "10-500 Hz. Default: 100 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 507, displayLabel: "TX Filter High Cut (SSB-DATA/AM-DATA)",      detail: "2500-4000 Hz. Default: 2900 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 508, displayLabel: "RX Filter Count",                            detail: "2 / 3 filters. Default: 3."),
    KenwoodMenuItem(group: "TX AND RX", number: 509, displayLabel: "Filter Control in SSB",                      detail: "Hi/Lo Cut / Shift and Width. Default: Hi/Lo Cut."),
    KenwoodMenuItem(group: "TX AND RX", number: 510, displayLabel: "Filter Control in SSB-DATA",                 detail: "Hi/Lo Cut / Shift and Width. Default: Shift and Width."),
    KenwoodMenuItem(group: "TX AND RX", number: 511, displayLabel: "VOX Voice Delay (Mic)",                      detail: "Off / Short / Middle / Long. Default: Middle."),
    KenwoodMenuItem(group: "TX AND RX", number: 512, displayLabel: "VOX Voice Delay (Non-Mic)",                  detail: "Off / Short / Middle / Long. Default: Middle."),

    // MARK: - REAR CONNECTORS (P2=06)

    KenwoodMenuItem(group: "REAR CONNECTORS", number: 600, displayLabel: "Baud Rate (COM)",                      detail: "4800-115200. Default: 9600."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 601, displayLabel: "Baud Rate (USB Standard)",              detail: "9600-115200. Default: 115200."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 602, displayLabel: "Baud Rate (USB Enhanced)",              detail: "9600-115200. Default: 115200."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 603, displayLabel: "Decoded Character Output",              detail: "Off / On. Default: Off."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 604, displayLabel: "Quick Data Transfer",                   detail: "Off / A (TX/RX) / A (Sub RX) / B. Default: Off."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 605, displayLabel: "USB Audio Input Level",                 detail: "0-100. Default: 50."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 606, displayLabel: "ACC 2 Audio Input Level",               detail: "0-100. Default: 50."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 607, displayLabel: "USB Audio Output Level",                detail: "0-100. Default: 100."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 608, displayLabel: "ACC 2 Audio Output Level",              detail: "0-100. Default: 50."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 609, displayLabel: "TX Monitor Level (Rear)",               detail: "Linked / 0-20. Default: Linked."),
    KenwoodMenuItem(group: "REAR CONNECTORS", number: 610, displayLabel: "Audio Output Type (Rear)",              detail: "All / RX Audio only. Default: All."),

    // MARK: - BANDSCOPE (P2=07)

    KenwoodMenuItem(group: "BANDSCOPE", number: 700, displayLabel: "Bandscope Display during TX",                detail: "Off / On. Default: Off."),
    KenwoodMenuItem(group: "BANDSCOPE", number: 701, displayLabel: "TX Audio Waveform",                          detail: "Off / On. Default: On."),
    KenwoodMenuItem(group: "BANDSCOPE", number: 702, displayLabel: "Bandscope Max Hold",                         detail: "10 s / Continuous. Default: 10 s."),
    KenwoodMenuItem(group: "BANDSCOPE", number: 703, displayLabel: "Waterfall when Tuning",                      detail: "Straight / Follow. Default: Straight."),
    KenwoodMenuItem(group: "BANDSCOPE", number: 704, displayLabel: "Waterfall Gradation Level",                  detail: "1-10. Default: 7."),

    // MARK: - ADVANCED (P1=1)

    KenwoodMenuItem(group: "ADVANCED", number: 10000, displayLabel: "External Meter 1 Signal Type",              detail: "Auto / Power / ALC / Drain V / COMP / Current / SWR. Default: Auto."),
    KenwoodMenuItem(group: "ADVANCED", number: 10001, displayLabel: "External Meter 2 Signal Type",              detail: "Auto / Power / ALC / Drain V / COMP / Current / SWR. Default: Auto."),
    KenwoodMenuItem(group: "ADVANCED", number: 10002, displayLabel: "External Meter 1 Level",                    detail: "0-100%. Default: 50%."),
    KenwoodMenuItem(group: "ADVANCED", number: 10003, displayLabel: "External Meter 2 Level",                    detail: "0-100%. Default: 50%."),
    KenwoodMenuItem(group: "ADVANCED", number: 10004, displayLabel: "Reference Oscillator Source",               detail: "Internal / External. Default: Internal."),
    KenwoodMenuItem(group: "ADVANCED", number: 10005, displayLabel: "Reference Oscillator Calibration",          detail: "0-1000. Default: 500."),
    KenwoodMenuItem(group: "ADVANCED", number: 10006, displayLabel: "TX Power Down (Transverter)",               detail: "Off / On. Default: On."),
    KenwoodMenuItem(group: "ADVANCED", number: 10007, displayLabel: "Antenna Tuner during RX",                   detail: "Off / On. Default: Off."),
    KenwoodMenuItem(group: "ADVANCED", number: 10008, displayLabel: "Antenna Tuner per Band",                    detail: "Off / On. Default: Off."),
    KenwoodMenuItem(group: "ADVANCED", number: 10009, displayLabel: "Mic Gain (FM)",                             detail: "0-100. Default: 50."),
    KenwoodMenuItem(group: "ADVANCED", number: 10010, displayLabel: "PKS Polarity Reverse",                      detail: "Off / On. Default: Off."),
]

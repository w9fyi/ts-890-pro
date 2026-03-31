// TS590MenuDefinitions.swift
//
// EX command parameter mapping for TS-590S and TS-590SG.
// TS-590S uses flat 3-digit EX numbering: EX{NNN}; where NNN = 000–087.
//
// Derived from the TS-590S/SG PC Command Reference.
// Items are grouped by function for display in the Radio Menu view.

import Foundation

let ts590MenuItems: [KenwoodMenuItem] = [

    // MARK: - DISPLAY & BEEP (000–006)

    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 0,   displayLabel: "Beep Volume",                        detail: "Confirmation beep volume. Off / 1-9. Default: 5."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 1,   displayLabel: "Beep (Band Edge)",                   detail: "Band edge beep. Off / On. Default: On."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 2,   displayLabel: "Display Brightness",                 detail: "Display brightness. 1-6 (auto). Default: Auto."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 3,   displayLabel: "Display Contrast",                   detail: "LCD contrast. 1-12. Default: 6."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 4,   displayLabel: "Display Backlight Color",            detail: "LCD backlight color. Amber / Green. Default: Amber."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 5,   displayLabel: "Display Illumination",               detail: "Display illumination. Off / On. Default: On."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 6,   displayLabel: "Screen Saver Function",              detail: "Screen saver. Off / On. Default: Off."),

    // MARK: - TUNING (007–017)

    KenwoodMenuItem(group: "TUNING", number: 7,   displayLabel: "Frequency Step Size (SSB/CW/FSK)",     detail: "Tuning step for SSB/CW/FSK mode Multi/CH control. 0.5/1/2.5/5/10 kHz. Default: 1 kHz."),
    KenwoodMenuItem(group: "TUNING", number: 8,   displayLabel: "Frequency Step Size (FM)",              detail: "Tuning step for FM mode Multi/CH control. 5/6.25/10/12.5/15/20/25/30/50/100 kHz. Default: 10 kHz."),
    KenwoodMenuItem(group: "TUNING", number: 9,   displayLabel: "Frequency Step Size (AM)",              detail: "Tuning step for AM mode Multi/CH control. 5/9/10/100 kHz. Default: 5 kHz."),
    KenwoodMenuItem(group: "TUNING", number: 10,  displayLabel: "Quick Tuning Step",                     detail: "Quick tuning step size. Off / 100/500/1000 kHz. Default: Off."),
    KenwoodMenuItem(group: "TUNING", number: 11,  displayLabel: "Tuning Steps per Revolution",           detail: "Steps per revolution of tuning control. 250/500/1000. Default: 500."),
    KenwoodMenuItem(group: "TUNING", number: 12,  displayLabel: "Tuning Speed Control",                  detail: "Fast-forward tuning acceleration. Off / On. Default: On."),
    KenwoodMenuItem(group: "TUNING", number: 13,  displayLabel: "Tuning Step Rounding",                  detail: "Round frequency to step size on Multi/CH operation. Off / On. Default: On."),
    KenwoodMenuItem(group: "TUNING", number: 14,  displayLabel: "RIT/XIT Speed (Step)",                  detail: "RIT/XIT speed in MULTI/CH or RIT/XIT control. Low / High. Default: Low."),
    KenwoodMenuItem(group: "TUNING", number: 15,  displayLabel: "Number of Band Memories",               detail: "Number of VFO band memories. 1/3/5. Default: 3."),
    KenwoodMenuItem(group: "TUNING", number: 16,  displayLabel: "Frequency Lock",                        detail: "Lock target. Dial Lock / Frequency Lock. Default: Frequency Lock."),
    KenwoodMenuItem(group: "TUNING", number: 17,  displayLabel: "Automatic Power Off (APO)",             detail: "Automatic power off. Off / 60/120/180 min. Default: Off."),

    // MARK: - MEMORY AND SCAN (018–023)

    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 18,  displayLabel: "Quick Memory Channels",              detail: "Number of quick memory channels. 3/5/10. Default: 5."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 19,  displayLabel: "Memory Channel Temporary Change",    detail: "Allow temporary frequency change in memory mode. Off / On. Default: Off."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 20,  displayLabel: "Program Slow Scan",                  detail: "Program slow scan. Off / On. Default: On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 21,  displayLabel: "Program Slow Scan Range",            detail: "Slow scan range. 100-500 Hz. Default: 300 Hz."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 22,  displayLabel: "Scan Hold",                          detail: "Scan hold. Off / On. Default: Off."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 23,  displayLabel: "Scan Resume Method",                 detail: "Scan resume condition. Time / Carrier. Default: Time."),

    // MARK: - CW (024–037)

    KenwoodMenuItem(group: "CW CONFIGURATION", number: 24,  displayLabel: "Paddle Type (Front Jack)",           detail: "Front PADDLE jack function. Straight / Paddle / Bug. Default: Paddle."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 25,  displayLabel: "Key Type (Rear Jack)",               detail: "Rear KEY jack function. Straight / Paddle / Bug. Default: Straight."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 26,  displayLabel: "Keyer Squeeze Mode",                 detail: "Keyer squeeze mode. A / B. Default: B."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 27,  displayLabel: "Dot/Dash Reverse",                   detail: "Swap dot/dash paddle. Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 28,  displayLabel: "Mic UP/DOWN as Paddle",              detail: "Mic UP/DOWN key operates as paddle. Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 29,  displayLabel: "CW Auto-TX in SSB Mode",             detail: "Auto CW TX when keying in SSB mode. Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 30,  displayLabel: "CW BFO Sideband",                    detail: "BFO sideband for CW mode. USB / LSB. Default: USB."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 31,  displayLabel: "CW Weight",                          detail: "Keyer weight ratio. Auto / 2.5-4.0. Default: Auto."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 32,  displayLabel: "CW Reversed Weight",                 detail: "Reversed keying auto weight. Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 33,  displayLabel: "CW Rise Time",                       detail: "CW rise time. 1/2/4/6 ms. Default: 6 ms."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 34,  displayLabel: "Contest Number Style",                detail: "Contest number style. Off / ANO / ANT / NO / NT. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 35,  displayLabel: "Contest Number",                      detail: "Contest number. 0001-9999. Default: 0001."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 36,  displayLabel: "CW Frequency Display",                detail: "CW frequency display offset. Off / On. Default: Off."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 37,  displayLabel: "CW Message Repeat Interval",          detail: "CW message repeat interval. 0-60 s. Default: 10 s."),

    // MARK: - FSK/PSK (038–043)

    KenwoodMenuItem(group: "FSK AND PSK", number: 38,  displayLabel: "FSK Shift Width",                    detail: "FSK shift width. 170/200/425/850 Hz. Default: 170 Hz."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 39,  displayLabel: "FSK Keying Polarity",                detail: "FSK keying polarity. Normal / Reverse. Default: Normal."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 40,  displayLabel: "FSK Tone Frequency",                 detail: "FSK tone frequency. 1275/2125 Hz. Default: 2125 Hz."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 41,  displayLabel: "TX UOS (Unshift on Space)",          detail: "TX unshift on space. Off / On. Default: On."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 42,  displayLabel: "Diddle",                             detail: "Diddle character. Off / Blank / Letters. Default: Blank."),
    KenwoodMenuItem(group: "FSK AND PSK", number: 43,  displayLabel: "New Line Code",                      detail: "New line code. CR+LF / All. Default: All."),

    // MARK: - TX/RX (044–061)

    KenwoodMenuItem(group: "TX AND RX", number: 44,  displayLabel: "TX Hold",                              detail: "TX hold timing. Off / 500 ms. Default: 500 ms."),
    KenwoodMenuItem(group: "TX AND RX", number: 45,  displayLabel: "Time-out Timer",                       detail: "Max continuous TX time. Off / 3/5/10/20/30 min. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 46,  displayLabel: "TX Inhibit",                           detail: "TX inhibit. Off / On. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 47,  displayLabel: "S-Meter Squelch Hang Time",            detail: "Squelch hang time. 0-1000 ms. Default: 250 ms."),
    KenwoodMenuItem(group: "TX AND RX", number: 48,  displayLabel: "FM Narrow Deviation",                  detail: "FM narrow mode deviation. 2.5 kHz / 5.0 kHz. Default: 2.5 kHz."),
    KenwoodMenuItem(group: "TX AND RX", number: 49,  displayLabel: "MULTI/CH Control Quick RIT",           detail: "Multi/CH control for RIT. Off / On. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 50,  displayLabel: "Beat Cancel 1",                        detail: "Beat Cancel 1 function. Off / On. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 51,  displayLabel: "Beat Cancel 2",                        detail: "Beat Cancel 2 function. Off / On. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 52,  displayLabel: "TX Power Fine Adjustment",             detail: "TX power fine (1W) step. Off / On. Default: Off."),
    KenwoodMenuItem(group: "TX AND RX", number: 53,  displayLabel: "TX Filter Low Cut (SSB)",              detail: "TX filter low cutoff (SSB). 10/100/200/300/400/500 Hz. Default: 300 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 54,  displayLabel: "TX Filter High Cut (SSB)",             detail: "TX filter high cutoff (SSB). 2500-5000 Hz. Default: 2700 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 55,  displayLabel: "TX Filter Low Cut (DATA)",             detail: "TX filter low cutoff (DATA). 10-500 Hz. Default: 100 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 56,  displayLabel: "TX Filter High Cut (DATA)",            detail: "TX filter high cutoff (DATA). 2500-5000 Hz. Default: 3500 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 57,  displayLabel: "Microphone Gain (FM)",                 detail: "Mic gain for FM mode. 0-100. Default: 50."),
    KenwoodMenuItem(group: "TX AND RX", number: 58,  displayLabel: "Speech Processor Mode",                detail: "Speech processor type. Soft / Hard. Default: Soft."),
    KenwoodMenuItem(group: "TX AND RX", number: 59,  displayLabel: "RX EQ (SSB)",                          detail: "RX equalizer (SSB). HB1/HB2/BB1/BB2/FLAT/User. Default: FLAT."),
    KenwoodMenuItem(group: "TX AND RX", number: 60,  displayLabel: "TX EQ (SSB)",                          detail: "TX equalizer (SSB). HB1/HB2/BB1/BB2/FLAT/User. Default: FLAT."),
    KenwoodMenuItem(group: "TX AND RX", number: 61,  displayLabel: "TX EQ (DATA)",                         detail: "TX equalizer (DATA). HB1/HB2/BB1/BB2/FLAT/User. Default: FLAT."),

    // MARK: - VOX (062–066)

    KenwoodMenuItem(group: "VOX", number: 62,  displayLabel: "VOX Gain",                               detail: "VOX gain. 0-9. Default: 5."),
    KenwoodMenuItem(group: "VOX", number: 63,  displayLabel: "VOX Delay",                              detail: "VOX delay. 150/250/500/750/1000/1500/2000/3000 ms. Default: 500 ms."),
    KenwoodMenuItem(group: "VOX", number: 64,  displayLabel: "Anti-VOX",                               detail: "Anti-VOX level. 0-9. Default: 5."),
    KenwoodMenuItem(group: "VOX", number: 65,  displayLabel: "DATA VOX",                               detail: "Data VOX. Off / On. Default: Off."),
    KenwoodMenuItem(group: "VOX", number: 66,  displayLabel: "VOX on DATA (Input Source)",              detail: "DATA VOX input. Rear / Front. Default: Rear."),

    // MARK: - AUDIO (067–078)

    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 67,  displayLabel: "Drive Output Level",                 detail: "DRV output level. 0-9. Default: 3."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 68,  displayLabel: "Audio Line Selection",               detail: "Audio line source for TX. ACC2 / USB. Default: ACC2."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 69,  displayLabel: "ACC2 AF Input Level",                detail: "ACC2 input level for data. 0-9. Default: 4."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 70,  displayLabel: "ACC2 AF Output Level",               detail: "ACC2 output level. 0-9. Default: 4."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 71,  displayLabel: "USB: Audio Input Level",             detail: "USB audio input level. 0-9. Default: 4."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 72,  displayLabel: "USB: Audio Output Level",            detail: "USB audio output level. 0-9. Default: 4."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 73,  displayLabel: "Beep Mix to ACC2/USB",               detail: "Mix beep tones into ACC2/USB audio output. Off / On. Default: Off."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 74,  displayLabel: "DATA VOX Gain (USB)",                detail: "DATA VOX gain (USB). 0-9. Default: 5."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 75,  displayLabel: "DATA VOX Delay (USB)",               detail: "DATA VOX delay (USB). 150-3000 ms. Default: 500 ms."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 76,  displayLabel: "Anti-VOX (USB)",                     detail: "Anti-VOX level (USB). 0-9. Default: 5."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 77,  displayLabel: "External Meter Output",              detail: "External meter signal. 1-8. Default: 1."),
    KenwoodMenuItem(group: "AUDIO AND CONNECTORS", number: 78,  displayLabel: "External Meter Output Level",        detail: "External meter level. 0-100. Default: 50."),

    // MARK: - COM / USB (079–087)

    KenwoodMenuItem(group: "COM AND USB", number: 79,  displayLabel: "Baud Rate (COM)",                     detail: "COM serial baud rate. 4800/9600/19200/38400/57600/115200. Default: 9600."),
    KenwoodMenuItem(group: "COM AND USB", number: 80,  displayLabel: "DTR Function (COM)",                  detail: "DTR pin function. Off / CW Keying / RTTY / PTT. Default: Off."),
    KenwoodMenuItem(group: "COM AND USB", number: 81,  displayLabel: "RTS Function (COM)",                  detail: "RTS pin function. Flow Control / CW Keying / RTTY / PTT. Default: Flow Control."),
    KenwoodMenuItem(group: "COM AND USB", number: 82,  displayLabel: "Baud Rate (USB)",                     detail: "USB virtual COM baud rate. 4800-115200. Default: 115200."),
    KenwoodMenuItem(group: "COM AND USB", number: 83,  displayLabel: "RTS Function (USB)",                  detail: "USB virtual COM RTS function. Off / CW Keying / RTTY / PTT. Default: Off."),
    KenwoodMenuItem(group: "COM AND USB", number: 84,  displayLabel: "DTR Function (USB)",                  detail: "USB virtual COM DTR function. Off / CW Keying / RTTY / PTT. Default: Off."),
    KenwoodMenuItem(group: "COM AND USB", number: 85,  displayLabel: "Decoded Character Output (COM)",      detail: "Output decoded characters to COM. Off / On. Default: Off."),
    KenwoodMenuItem(group: "COM AND USB", number: 86,  displayLabel: "Decoded Character Output (USB)",      detail: "Output decoded characters to USB. Off / On. Default: Off."),
    KenwoodMenuItem(group: "COM AND USB", number: 87,  displayLabel: "PKS Polarity",                        detail: "PKS pin polarity. Off / On. Default: Off."),
]

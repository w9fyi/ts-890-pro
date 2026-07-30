// TS590MenuDefinitions.swift
//
// EX command parameter mapping for the TS-590S and TS-590SG.
// TS-590S:  flat 3-digit EX numbering, menus 000–087.
// TS-590SG: flat 3-digit EX numbering, menus 000–099 (every item is
//           renumbered relative to the S — the two tables cannot be shared).
//
// Transcribed from the official Kenwood "TS-590S/TS-590SG PC CONTROL COMMAND
// Reference Guide" rev 3 (B5A-0316, January 2019), EX Command Parameter Lists.
// Items are grouped by function for display in the Radio Menu view.

import Foundation

// MARK: - TS-590S (menus 000–087)

let ts590MenuItems: [KenwoodMenuItem] = [

    // MARK: DISPLAY, BEEP & VOICE GUIDE (000–009)

    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 0,   displayLabel: "Display Brightness",                 detail: "Display brightness. Off / 1-6."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 1,   displayLabel: "Backlight Color",                    detail: "LCD backlight color. 1 (Amber) / 2 (Green)."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 2,   displayLabel: "Panel Key Double-Function Response", detail: "Key response time for double function. 1/2/3."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 3,   displayLabel: "Beep Volume",                        detail: "Confirmation beep volume. Off / 1-9."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 4,   displayLabel: "Sidetone Volume",                    detail: "CW sidetone volume. Off / 1-9."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 5,   displayLabel: "Message Playback Volume",            detail: "Voice/CW message playback volume. Off / 1-9."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 6,   displayLabel: "Voice Guide Volume",                 detail: "Voice guide volume. Off / 1-7."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 7,   displayLabel: "Voice Guide Speed",                  detail: "Voice guide speed. 0-4."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 8,   displayLabel: "Voice Guide Language",               detail: "Voice guide language. EN / JP."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 9,   displayLabel: "Auto Announcement",                  detail: "Automatic voice announcement. Off / On."),

    // MARK: TUNING (010–016)

    KenwoodMenuItem(group: "TUNING", number: 10,  displayLabel: "MHz Step",                              detail: "MHz up/down step. 0.1 / 0.5 / 1 MHz."),
    KenwoodMenuItem(group: "TUNING", number: 11,  displayLabel: "Tuning Control Adjustment Rate",        detail: "Tuning control rate. 250/500/1000 Hz per revolution step."),
    KenwoodMenuItem(group: "TUNING", number: 12,  displayLabel: "MULTI/CH Control Rounding",             detail: "Round frequency when using MULTI/CH. Off / On."),
    KenwoodMenuItem(group: "TUNING", number: 13,  displayLabel: "Step Change Inside BC Band (AM)",       detail: "Dedicated 9 kHz step inside the broadcast band. Off / On."),
    KenwoodMenuItem(group: "TUNING", number: 14,  displayLabel: "MULTI/CH Step (SSB/CW/FSK)",            detail: "MULTI/CH step for SSB/CW/FSK. 0.5/1/2.5/5/10 kHz."),
    KenwoodMenuItem(group: "TUNING", number: 15,  displayLabel: "MULTI/CH Step (AM)",                    detail: "MULTI/CH step for AM. 5/6.25/10/12.5/15/20/25/30/50/100 kHz."),
    KenwoodMenuItem(group: "TUNING", number: 16,  displayLabel: "MULTI/CH Step (FM)",                    detail: "MULTI/CH step for FM. 5/6.25/10/12.5/15/20/25/30/50/100 kHz."),

    // MARK: MEMORY AND SCAN (017–023)

    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 17,  displayLabel: "Quick Memory Channels",              detail: "Number of quick memory channels. 3/5/10."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 18,  displayLabel: "Memory Frequency Temporary Change",  detail: "Allow temporary change of standard memory frequency. Off / On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 19,  displayLabel: "Program Slow Scan",                  detail: "Program scan slow down. Off / On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 20,  displayLabel: "Program Slow Scan Range",            detail: "Slow scan frequency range. 100/200/300/400/500 Hz."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 21,  displayLabel: "Program Scan Hold",                  detail: "Scan hold. Off / On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 22,  displayLabel: "Scan Resume Method",                 detail: "Scan resume condition. TO (time) / CO (carrier)."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 23,  displayLabel: "Auto Mode Change",                   detail: "Automatic mode change by frequency. Off / On."),

    // MARK: RX / TX FILTERS AND EQ (024–031)

    KenwoodMenuItem(group: "TX AND RX", number: 24,  displayLabel: "Auto Notch Tracking Speed",            detail: "Following speed of AUTO NOTCH. 0-4."),
    KenwoodMenuItem(group: "TX AND RX", number: 25,  displayLabel: "TX Filter Low Cut (SSB/AM)",           detail: "TX filter low cutoff for SSB/AM. 10/100/200/300/400/500 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 26,  displayLabel: "TX Filter High Cut (SSB/AM)",          detail: "TX filter high cutoff for SSB/AM. 2500-3000 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 27,  displayLabel: "TX Filter Low Cut (SSB-DATA)",         detail: "TX filter low cutoff for SSB-DATA. 10/100/200/300/400/500 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 28,  displayLabel: "TX Filter High Cut (SSB-DATA)",        detail: "TX filter high cutoff for SSB-DATA. 2500-3000 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 29,  displayLabel: "Speech Processor Mode",                detail: "Speech processor effect. Soft / Hard."),
    KenwoodMenuItem(group: "TX AND RX", number: 30,  displayLabel: "TX Equalizer",                         detail: "Transmit equalizer. Off/HB1/HB2/FP/BB1/BB2/C/U."),
    KenwoodMenuItem(group: "TX AND RX", number: 31,  displayLabel: "RX Equalizer",                         detail: "Receive equalizer. Off/HB1/HB2/FP/BB1/BB2/FLAT/U."),

    // MARK: CW (032–043)

    KenwoodMenuItem(group: "CW CONFIGURATION", number: 32,  displayLabel: "Keyer Mode",                         detail: "Electronic keyer operation mode. A / B."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 33,  displayLabel: "Insert Keying",                      detail: "Interrupt keying (insert). Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 34,  displayLabel: "Sidetone / Pitch Frequency",         detail: "Sidetone and pitch. 300-1000 Hz in 50 Hz steps."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 35,  displayLabel: "CW Rise Time",                       detail: "CW keying rise time (clipping). 1/2/4/6 ms."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 36,  displayLabel: "Keying Weight Ratio",                detail: "Keyer weight ratio. Auto / 2.5-4.0."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 37,  displayLabel: "Reverse Auto Weight",                detail: "Reversed keying auto weight ratio. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 38,  displayLabel: "Bug Key Function",                   detail: "Bug (semi-automatic) key mode. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 39,  displayLabel: "Dot/Dash Reverse",                   detail: "Swap paddle dot/dash. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 40,  displayLabel: "Mic Paddle Function",                detail: "Mic UP/DWN keys act as paddle. PF / PA."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 41,  displayLabel: "Auto CW TX in SSB",                  detail: "Auto CW transmit when keying in SSB mode. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 42,  displayLabel: "SSB→CW Frequency Correction",        detail: "Frequency correction when changing SSB to CW. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 43,  displayLabel: "Break-in Null Setting",              detail: "Break-in null configuration at keying speed change. Off / On."),

    // MARK: FSK (044–046)

    KenwoodMenuItem(group: "FSK", number: 44,  displayLabel: "FSK Shift Width",                    detail: "FSK shift. 170/200/425/850 Hz."),
    KenwoodMenuItem(group: "FSK", number: 45,  displayLabel: "FSK Keying Polarity",                detail: "FSK keying polarity (reverse). Off / On."),
    KenwoodMenuItem(group: "FSK", number: 46,  displayLabel: "FSK Tone Frequency",                 detail: "FSK tone frequency. 1275 / 2125 Hz."),

    // MARK: TX AND RX (047–060)

    KenwoodMenuItem(group: "TX AND RX", number: 47,  displayLabel: "Microphone Gain (FM)",                 detail: "Mic gain for FM. 1 (low) / 2 (mid) / 3 (high)."),
    KenwoodMenuItem(group: "TX AND RX", number: 48,  displayLabel: "TX Power Fine Adjustment",             detail: "Fine (1 W) transmit power steps. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 49,  displayLabel: "Time-out Timer",                       detail: "Maximum continuous TX time. Off / 3/5/10/20/30 min."),
    KenwoodMenuItem(group: "TX AND RX", number: 50,  displayLabel: "Transverter / Power Down",             detail: "Transverter function and power down. Off / 1 / 2."),
    KenwoodMenuItem(group: "TX AND RX", number: 51,  displayLabel: "TX Hold After AT Tune",                detail: "Hold TX when the antenna tuner completes tuning. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 52,  displayLabel: "AT While Receiving",                   detail: "Antenna tuner in-line during RX. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 53,  displayLabel: "HF Linear Amplifier Control",          detail: "HF linear amp relay/delay control. Off / 1 / 2 / 3."),
    KenwoodMenuItem(group: "TX AND RX", number: 54,  displayLabel: "50 MHz Linear Amplifier Control",      detail: "50 MHz linear amp relay/delay control. Off / 1 / 2 / 3."),
    KenwoodMenuItem(group: "TX AND RX", number: 55,  displayLabel: "Constant Recording",                   detail: "Constant audio recording. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 56,  displayLabel: "Message Playback Repeat",              detail: "Voice/CW message playback repeat. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 57,  displayLabel: "Message Repeat Interval",              detail: "Playback repeat interval. 0-60 s."),
    KenwoodMenuItem(group: "TX AND RX", number: 58,  displayLabel: "Split Transfer Function",              detail: "Split frequency transfer. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 59,  displayLabel: "Write Split Transfer to VFO",          detail: "Write transferred split data to the VFO. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 60,  displayLabel: "TX Inhibit",                           detail: "Transmit inhibit. Off / On."),

    // MARK: COM / USB PORT (061–062)

    KenwoodMenuItem(group: "COM AND USB", number: 61,  displayLabel: "Baud Rate (COM)",                     detail: "COM port speed. 4800/9600/19200/38400/57600/115200 bps."),
    KenwoodMenuItem(group: "COM AND USB", number: 62,  displayLabel: "Baud Rate (USB)",                     detail: "USB virtual COM port speed. 4800/9600/19200/38400/57600/115200 bps."),

    // MARK: AUDIO & DATA I/O (063–074)

    KenwoodMenuItem(group: "AUDIO AND DATA", number: 63,  displayLabel: "DATA Modulation Line",               detail: "Audio input line for data communications. ACC2 / USB. Default: ACC2. Must be USB for TX audio from this app."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 64,  displayLabel: "USB Audio Input Level",              detail: "USB audio input (TX) level for data. 0-9. Default: 4."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 65,  displayLabel: "USB Audio Output Level",             detail: "USB audio output (RX) level for data. 0-9. Default: 4."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 66,  displayLabel: "ACC2 AF Input Level",                detail: "ACC2 terminal AF input level. 0-9."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 67,  displayLabel: "ACC2 AF Output Level",               detail: "ACC2 terminal AF output level. 0-9."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 68,  displayLabel: "Beep Mix to ACC2/USB",               detail: "Mix beep tones into external (ACC2/USB) audio outputs. Off / On. Keep Off for data modes."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 69,  displayLabel: "DATA VOX",                           detail: "VOX for audio on the rear (data) input. Off / On. Keep Off when the PC stays connected."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 70,  displayLabel: "DATA VOX Delay",                     detail: "DATA VOX delay. 0-100 in steps of 5."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 71,  displayLabel: "DATA VOX Gain (USB)",                detail: "DATA VOX gain for USB audio input. 0-9."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 72,  displayLabel: "DATA VOX Gain (ACC2)",               detail: "DATA VOX gain for ACC2 terminal input. 0-9."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 73,  displayLabel: "PKS Polarity",                       detail: "ACC2 PKS pin polarity change. Off / On."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 74,  displayLabel: "Busy Transmit Inhibit",              detail: "Inhibit TX while busy. Off / On."),

    // MARK: FM / CONNECTOR MISC (075–078)

    KenwoodMenuItem(group: "MISC", number: 75,  displayLabel: "CTCSS Mute Operation",               detail: "CTCSS mute operation change. 1 / 2."),
    KenwoodMenuItem(group: "MISC", number: 76,  displayLabel: "PSQ Control Signal Logic",           detail: "PSQ control signal logic. LO / OPEN."),
    KenwoodMenuItem(group: "MISC", number: 77,  displayLabel: "PSQ Output Condition",               detail: "PSQ output condition. Off/BSY/SQL/SND/BSY-SND/SQL-SND."),
    KenwoodMenuItem(group: "MISC", number: 78,  displayLabel: "Automatic Power Off (APO)",          detail: "Automatic power off. Off / 60/120/180 min."),

    // MARK: PF KEYS (079–086)

    KenwoodMenuItem(group: "PF KEYS", number: 79,  displayLabel: "Panel PF A Function",                 detail: "Front panel PF A key. 000-255 (255 = off). 205 = DATA SEND."),
    KenwoodMenuItem(group: "PF KEYS", number: 80,  displayLabel: "Panel PF B Function",                 detail: "Front panel PF B key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 81,  displayLabel: "Mic PF 1 Function",                   detail: "Microphone PF 1 key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 82,  displayLabel: "Mic PF 2 Function",                   detail: "Microphone PF 2 key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 83,  displayLabel: "Mic PF 3 Function",                   detail: "Microphone PF 3 key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 84,  displayLabel: "Mic PF 4 Function",                   detail: "Microphone PF 4 key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 85,  displayLabel: "Mic PF (DWN) Function",               detail: "Microphone DWN key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 86,  displayLabel: "Mic PF (UP) Function",                detail: "Microphone UP key. 000-255 (255 = off)."),

    // MARK: MISC (087)

    KenwoodMenuItem(group: "MISC", number: 87,  displayLabel: "Power-On Message",                   detail: "Power-on message. Up to 8 ASCII characters."),
]

// MARK: - TS-590SG (menus 000–099)

let ts590sgMenuItems: [KenwoodMenuItem] = [

    // MARK: FIRMWARE, DISPLAY, BEEP & VOICE GUIDE (000–011)

    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 0,   displayLabel: "Firmware Version",                   detail: "Firmware version (read only)."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 1,   displayLabel: "Power-On Message",                   detail: "Power-on message. Up to 8 ASCII characters."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 2,   displayLabel: "Display Brightness",                 detail: "Display brightness. Off / 1-6."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 3,   displayLabel: "Backlight Color",                    detail: "LCD backlight color. 1-10."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 4,   displayLabel: "Panel Key Double-Function Response", detail: "Key response time for double function. 1/2/3."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 5,   displayLabel: "Beep Volume",                        detail: "Confirmation beep volume. Off / 1-20."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 6,   displayLabel: "Sidetone Volume",                    detail: "CW sidetone volume. Off / 1-20."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 7,   displayLabel: "Message Playback Volume",            detail: "Voice/CW message playback volume. Off / 1-20."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 8,   displayLabel: "Voice Guide Volume",                 detail: "Voice guide volume. Off / 1-20."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 9,   displayLabel: "Voice Guide Speed",                  detail: "Voice guide speed. 0-4."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 10,  displayLabel: "Voice Guide Language",               detail: "Voice guide language. EN / JP."),
    KenwoodMenuItem(group: "DISPLAY AND BEEP", number: 11,  displayLabel: "Auto Announcement",                  detail: "Automatic voice announcement. Off / 1 / 2."),

    // MARK: TUNING (012–019)

    KenwoodMenuItem(group: "TUNING", number: 12,  displayLabel: "MHz Step",                              detail: "MHz up/down step. 0.1 / 0.5 / 1 MHz."),
    KenwoodMenuItem(group: "TUNING", number: 13,  displayLabel: "Tuning Control Adjustment Rate",        detail: "Tuning control rate. 250/500/1000 Hz per revolution step."),
    KenwoodMenuItem(group: "TUNING", number: 14,  displayLabel: "MULTI/CH Control Rounding",             detail: "Round frequency when using MULTI/CH. Off / On."),
    KenwoodMenuItem(group: "TUNING", number: 15,  displayLabel: "Step Change Inside BC Band (AM)",       detail: "Dedicated 9 kHz step inside the broadcast band. Off / On."),
    KenwoodMenuItem(group: "TUNING", number: 16,  displayLabel: "MULTI/CH Step (SSB)",                   detail: "MULTI/CH step for SSB. Off/0.5/1/2.5/5/10 kHz."),
    KenwoodMenuItem(group: "TUNING", number: 17,  displayLabel: "MULTI/CH Step (CW/FSK)",                detail: "MULTI/CH step for CW/FSK. Off/0.5/1/2.5/5/10 kHz."),
    KenwoodMenuItem(group: "TUNING", number: 18,  displayLabel: "MULTI/CH Step (AM)",                    detail: "MULTI/CH step for AM. Off/5/6.25/10/12.5/15/20/25/30/50/100 kHz."),
    KenwoodMenuItem(group: "TUNING", number: 19,  displayLabel: "MULTI/CH Step (FM)",                    detail: "MULTI/CH step for FM. Off/5/6.25/10/12.5/15/20/25/30/50/100 kHz."),

    // MARK: MEMORY AND SCAN (020–027)

    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 20,  displayLabel: "Shiftable RX Frequency in Split TX",  detail: "Allow RX frequency shift during split transmission. Off / On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 21,  displayLabel: "Quick Memory Channels",              detail: "Number of quick memory channels. 3/5/10."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 22,  displayLabel: "Memory Frequency Temporary Change",  detail: "Temporary change of standard/extension memory frequency. Off / On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 23,  displayLabel: "Program Slow Scan",                  detail: "Program scan slow down. Off / On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 24,  displayLabel: "Program Slow Scan Range",            detail: "Slow scan frequency range. 100/200/300/400/500 Hz."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 25,  displayLabel: "Program Scan Hold",                  detail: "Scan hold. Off / On."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 26,  displayLabel: "Scan Resume Method",                 detail: "Scan resume condition. TO (time) / CO (carrier)."),
    KenwoodMenuItem(group: "MEMORY AND SCAN", number: 27,  displayLabel: "Auto Mode Change",                   detail: "Automatic mode change by frequency. Off / On."),

    // MARK: RX / TX FILTERS AND EQ (028–037)

    KenwoodMenuItem(group: "TX AND RX", number: 28,  displayLabel: "Filter Control Method (SSB)",          detail: "Low Cut/High Cut vs Width/Shift for SSB. 1 (HI/LO) / 2 (WIDTH/SHIFT)."),
    KenwoodMenuItem(group: "TX AND RX", number: 29,  displayLabel: "Filter Control Method (SSB-DATA)",     detail: "Low Cut/High Cut vs Width/Shift for SSB-DATA. 1 (HI/LO) / 2 (WIDTH/SHIFT)."),
    KenwoodMenuItem(group: "TX AND RX", number: 30,  displayLabel: "Auto Notch Tracking Speed",            detail: "Following speed of AUTO NOTCH. 0-4."),
    KenwoodMenuItem(group: "TX AND RX", number: 31,  displayLabel: "TX Filter Low Cut (SSB/AM)",           detail: "TX filter low cutoff for SSB/AM. 10/100/200/300/400/500 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 32,  displayLabel: "TX Filter High Cut (SSB/AM)",          detail: "TX filter high cutoff for SSB/AM. 2500-3000 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 33,  displayLabel: "TX Filter Low Cut (SSB-DATA)",         detail: "TX filter low cutoff for SSB-DATA. 10/100/200/300/400/500 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 34,  displayLabel: "TX Filter High Cut (SSB-DATA)",        detail: "TX filter high cutoff for SSB-DATA. 2500-3000 Hz."),
    KenwoodMenuItem(group: "TX AND RX", number: 35,  displayLabel: "Speech Processor Mode",                detail: "Speech processor effect. Soft / Hard."),
    KenwoodMenuItem(group: "TX AND RX", number: 36,  displayLabel: "TX Equalizer",                         detail: "Transmit equalizer. Off/HB1/HB2/FP/BB1/BB2/C/U."),
    KenwoodMenuItem(group: "TX AND RX", number: 37,  displayLabel: "RX Equalizer",                         detail: "Receive equalizer. Off/HB1/HB2/FP/BB1/BB2/FLAT/U."),

    // MARK: CW (038–049)

    KenwoodMenuItem(group: "CW CONFIGURATION", number: 38,  displayLabel: "Keyer Mode",                         detail: "Electronic keyer operation mode. A / B."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 39,  displayLabel: "Insert Keying",                      detail: "Interrupt keying (insert). Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 40,  displayLabel: "Sidetone / Pitch Frequency",         detail: "Sidetone and pitch. 300-1000 Hz in 50 Hz steps."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 41,  displayLabel: "CW Rise Time",                       detail: "CW keying rise time (clipping). 1/2/4/6 ms."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 42,  displayLabel: "Keying Weight Ratio",                detail: "Keyer weight ratio. Auto / 2.5-4.0."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 43,  displayLabel: "Reverse Auto Weight",                detail: "Reversed keying auto weight ratio. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 44,  displayLabel: "Bug Key Function",                   detail: "Bug (semi-automatic) key mode. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 45,  displayLabel: "Dot/Dash Reverse",                   detail: "Swap paddle dot/dash. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 46,  displayLabel: "Mic Paddle Function",                detail: "Mic UP/DWN keys act as paddle. PF / PA."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 47,  displayLabel: "Auto CW TX in SSB",                  detail: "Auto CW transmit when keying in SSB mode. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 48,  displayLabel: "SSB→CW Frequency Correction",        detail: "Frequency correction when changing SSB to CW. Off / On."),
    KenwoodMenuItem(group: "CW CONFIGURATION", number: 49,  displayLabel: "Break-in Null Setting",              detail: "Break-in null configuration at keying speed change. Off / On."),

    // MARK: FSK (050–052)

    KenwoodMenuItem(group: "FSK", number: 50,  displayLabel: "FSK Shift Width",                    detail: "FSK shift. 170/200/425/850 Hz."),
    KenwoodMenuItem(group: "FSK", number: 51,  displayLabel: "FSK Keying Polarity",                detail: "FSK keying polarity (reverse). Off / On."),
    KenwoodMenuItem(group: "FSK", number: 52,  displayLabel: "FSK Tone Frequency",                 detail: "FSK tone frequency. 1275 / 2125 Hz."),

    // MARK: TX AND RX (053–066)

    KenwoodMenuItem(group: "TX AND RX", number: 53,  displayLabel: "Microphone Gain (FM)",                 detail: "Mic gain for FM. 1 (low) / 2 (mid) / 3 (high)."),
    KenwoodMenuItem(group: "TX AND RX", number: 54,  displayLabel: "TX Power Fine Adjustment",             detail: "Fine (1 W) transmit power steps. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 55,  displayLabel: "Time-out Timer",                       detail: "Maximum continuous TX time. Off / 3/5/10/20/30 min."),
    KenwoodMenuItem(group: "TX AND RX", number: 56,  displayLabel: "Transverter / Power Down",             detail: "Transverter function and power down. Off / 1 / 2."),
    KenwoodMenuItem(group: "TX AND RX", number: 57,  displayLabel: "TX Hold After AT Tune",                detail: "Hold TX when the antenna tuner completes tuning. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 58,  displayLabel: "AT While Receiving",                   detail: "Antenna tuner in-line during RX. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 59,  displayLabel: "HF Linear Amplifier Control",          detail: "HF linear amp relay/delay control. Off / 1-5."),
    KenwoodMenuItem(group: "TX AND RX", number: 60,  displayLabel: "50 MHz Linear Amplifier Control",      detail: "50 MHz linear amp relay/delay control. Off / 1-5."),
    KenwoodMenuItem(group: "TX AND RX", number: 61,  displayLabel: "Constant Recording",                   detail: "Constant audio recording. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 62,  displayLabel: "Message Playback Repeat",              detail: "Voice/CW message playback repeat. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 63,  displayLabel: "Message Repeat Interval",              detail: "Playback repeat interval. 0-60 s."),
    KenwoodMenuItem(group: "TX AND RX", number: 64,  displayLabel: "Split Transfer Function",              detail: "Split frequency transfer. Off / A-T R / A-SUB R / B."),
    KenwoodMenuItem(group: "TX AND RX", number: 65,  displayLabel: "Write Split Transfer to VFO",          detail: "Write transferred split data to the VFO. Off / On."),
    KenwoodMenuItem(group: "TX AND RX", number: 66,  displayLabel: "TX Inhibit",                           detail: "Transmit inhibit. Off / On."),

    // MARK: COM / USB PORT (067–068)

    KenwoodMenuItem(group: "COM AND USB", number: 67,  displayLabel: "Baud Rate (COM)",                     detail: "COM port speed. 4800/9600/19200/38400/57600/115200 bps."),
    KenwoodMenuItem(group: "COM AND USB", number: 68,  displayLabel: "Baud Rate (USB)",                     detail: "USB virtual COM port speed. 4800/9600/19200/38400/57600/115200 bps."),

    // MARK: AUDIO & DATA I/O (069–081)

    KenwoodMenuItem(group: "AUDIO AND DATA", number: 69,  displayLabel: "DATA Modulation Line",               detail: "Audio input line for data communications. ACC2 / USB. Default: ACC2. Must be USB for TX audio from this app."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 70,  displayLabel: "SEND/PTT Audio Source (Data Mode)",  detail: "Audio source of SEND/PTT transmission in data mode. FRONT / REAR."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 71,  displayLabel: "USB Audio Input Level",              detail: "USB audio input (TX) level for data. 0-9. Default: 4."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 72,  displayLabel: "USB Audio Output Level",             detail: "USB audio output (RX) level for data. 0-9. Default: 4."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 73,  displayLabel: "ACC2 AF Input Level",                detail: "ACC2 terminal AF input level. 0-9."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 74,  displayLabel: "ACC2 AF Output Level",               detail: "ACC2 terminal AF output level. 0-9."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 75,  displayLabel: "Beep Mix to ACC2/USB",               detail: "Mix beep tones into external (ACC2/USB) audio outputs. Off / On. Keep Off for data modes."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 76,  displayLabel: "DATA VOX",                           detail: "VOX for audio on the rear (data) input. Off / On. Keep Off when the PC stays connected."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 77,  displayLabel: "DATA VOX Delay",                     detail: "DATA VOX delay. 0-100 in steps of 5."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 78,  displayLabel: "DATA VOX Gain (USB)",                detail: "DATA VOX gain for USB audio input. 0-9."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 79,  displayLabel: "DATA VOX Gain (ACC2)",               detail: "DATA VOX gain for ACC2 terminal input. 0-9."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 80,  displayLabel: "PKS Polarity",                       detail: "ACC2 PKS pin polarity change. Off / On."),
    KenwoodMenuItem(group: "AUDIO AND DATA", number: 81,  displayLabel: "Busy Transmit Inhibit",              detail: "Inhibit TX while busy. Off / On."),

    // MARK: FM / CONNECTOR MISC (082–086)

    KenwoodMenuItem(group: "MISC", number: 82,  displayLabel: "CTCSS Mute Operation",               detail: "CTCSS mute operation change. 1 / 2."),
    KenwoodMenuItem(group: "MISC", number: 83,  displayLabel: "PSQ Control Signal Logic",           detail: "PSQ control signal logic. LO / OPEN."),
    KenwoodMenuItem(group: "MISC", number: 84,  displayLabel: "PSQ Output Condition",               detail: "PSQ output condition. Off/BSY/SQL/SND/BSY-SND/SQL-SND."),
    KenwoodMenuItem(group: "MISC", number: 85,  displayLabel: "DRV Connector Output",               detail: "DRV connector output function. DRO / ANT."),
    KenwoodMenuItem(group: "MISC", number: 86,  displayLabel: "Automatic Power Off (APO)",          detail: "Automatic power off. Off / 60/120/180 min."),

    // MARK: PF KEYS (087–099)

    KenwoodMenuItem(group: "PF KEYS", number: 87,  displayLabel: "Panel PF A Function",                 detail: "Front panel PF A key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 88,  displayLabel: "Panel PF B Function",                 detail: "Front panel PF B key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 89,  displayLabel: "RIT Key Function",                    detail: "RIT key assignment. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 90,  displayLabel: "XIT Key Function",                    detail: "XIT key assignment. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 91,  displayLabel: "CL Key Function",                     detail: "CL key assignment. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 92,  displayLabel: "MULTI/CH Key (Non-CW)",               detail: "Front panel MULTI/CH key assignment outside CW mode. 000-255."),
    KenwoodMenuItem(group: "PF KEYS", number: 93,  displayLabel: "MULTI/CH Key (CW)",                   detail: "Front panel MULTI/CH key assignment in CW mode. 000-255."),
    KenwoodMenuItem(group: "PF KEYS", number: 94,  displayLabel: "Mic PF 1 Function",                   detail: "Microphone PF 1 key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 95,  displayLabel: "Mic PF 2 Function",                   detail: "Microphone PF 2 key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 96,  displayLabel: "Mic PF 3 Function",                   detail: "Microphone PF 3 key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 97,  displayLabel: "Mic PF 4 Function",                   detail: "Microphone PF 4 key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 98,  displayLabel: "Mic PF (DWN) Function",               detail: "Microphone DWN key. 000-255 (255 = off)."),
    KenwoodMenuItem(group: "PF KEYS", number: 99,  displayLabel: "Mic PF (UP) Function",                detail: "Microphone UP key. 000-255 (255 = off)."),
]

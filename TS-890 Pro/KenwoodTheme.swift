//
//  KenwoodTheme.swift
//  Kenwood control
//
//  Centralized color palette and visual constants styled after TS-Control:
//  neutral macOS dark grays, white VFO digits on black, and color used only
//  for state — red = TX, green = active RX functions, blue = selection/passband.
//

import SwiftUI

enum KenwoodTheme {

    // MARK: - State colors

    /// Blue — selected/highlight state, filter passband, scope accents
    static let blue = Color(red: 0.04, green: 0.40, blue: 0.85)

    /// Lighter blue for outlines and highlights
    static let blueLight = Color(red: 0.25, green: 0.55, blue: 0.95)

    /// Green — active RX function buttons (NR, NB, AGC, …)
    static let activeGreen = Color(red: 0.13, green: 0.62, blue: 0.25)

    /// Translucent blue fill for the RX filter passband overlay on the scope
    static let passbandBlue = Color(red: 0.30, green: 0.55, blue: 0.85).opacity(0.30)

    // MARK: - VFO digits

    /// Primary VFO frequency digits — white on black
    static let digitsPrimary = Color.white

    /// Sub/inactive VFO digits — dimmed white
    static let digitsSecondary = Color(white: 0.62)

    // MARK: - Chassis / surface colors

    /// Main window background — near black
    static let chassis = Color(red: 0.11, green: 0.11, blue: 0.12)

    /// Slightly lighter panel surface for cards and sections
    static let panel = Color(red: 0.16, green: 0.16, blue: 0.165)

    /// Button inactive background — flat dark gray
    static let buttonInactive = Color(red: 0.23, green: 0.23, blue: 0.24)

    /// Subtle border/divider color
    static let border = Color(white: 0.28)

    // MARK: - Meter colors

    /// Meter face background arc
    static let meterFace = Color(white: 0.18)

    /// Meter green zone (normal)
    static let meterGreen = Color(red: 0.20, green: 0.75, blue: 0.30)

    /// Meter amber zone (caution)
    static let meterAmber = Color(red: 1.0, green: 0.72, blue: 0.20)

    /// Meter red zone (warning)
    static let meterRed = Color(red: 0.95, green: 0.20, blue: 0.15)

    /// Meter needle color
    static let needle = Color.white

    /// Meter pivot dot
    static let pivot = Color(white: 0.85)

    // MARK: - Scope colors

    /// Spectrum filled area
    static let spectrumFill = Color(red: 0.10, green: 0.32, blue: 0.16).opacity(0.75)

    /// Spectrum outline trace
    static let spectrumOutline = Color(red: 0.45, green: 0.95, blue: 0.45)

    /// Scope grid lines
    static let scopeGrid = Color(white: 0.16)

    /// Scope background
    static let scopeBackground = Color(red: 0.02, green: 0.02, blue: 0.03)

    /// Frequency axis text
    static let scopeFreqText = Color(white: 0.65)

    /// Frequency ruler band background (between spectrum and waterfall)
    static let scopeRulerBackground = Color(red: 0.13, green: 0.13, blue: 0.14)

    /// Center marker on scope
    static let scopeCenterMarker = Color(red: 0.95, green: 0.35, blue: 0.30).opacity(0.7)

    // MARK: - Inline meter bar colors

    /// S-meter bar
    static let barS = Color(red: 0.20, green: 0.75, blue: 0.30)

    /// Power bar
    static let barPower = Color(red: 0.25, green: 0.60, blue: 0.95)

    /// SWR bar
    static let barSWR = Color(red: 1.0, green: 0.55, blue: 0.15)

    /// ALC bar
    static let barALC = Color(red: 0.95, green: 0.20, blue: 0.15)

    /// Bar background trough
    static let barBackground = Color(white: 0.12)

    // MARK: - TX/RX indicator

    /// TX active (transmitting)
    static let txRed = Color(red: 0.85, green: 0.15, blue: 0.12)

    /// RX idle dot
    static let rxIdle = Color(white: 0.20)

    // MARK: - Text

    /// Secondary label text (row headers, meter labels)
    static let labelSecondary = Color(white: 0.60)

    // MARK: - Animation

    /// Spring for meter needle sweep — mimics a real analog movement
    static let needleSpring = Animation.interpolatingSpring(
        mass: 0.4, stiffness: 80, damping: 8, initialVelocity: 0
    )
}

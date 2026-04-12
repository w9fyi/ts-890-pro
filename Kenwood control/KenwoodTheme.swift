//
//  KenwoodTheme.swift
//  Kenwood control
//
//  Centralized color palette and visual constants inspired by the TS-890S front panel.
//  Dark charcoal chassis, amber VFO digits, Kenwood blue bandscope, amber-backlit buttons.
//

import SwiftUI

enum KenwoodTheme {

    // MARK: - Kenwood brand colors

    /// Deep Kenwood blue — bandscope fills, active indicators, accent
    static let blue = Color(red: 0.0, green: 0.30, blue: 0.55)

    /// Lighter Kenwood blue for outlines and highlights
    static let blueLight = Color(red: 0.15, green: 0.50, blue: 0.80)

    /// Warm amber — VFO A digits, active button glow, needle highlights
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.20)

    /// Dimmer amber — VFO B digits, secondary indicators
    static let amberDim = Color(red: 0.80, green: 0.58, blue: 0.18)

    /// Amber tint for button active backgrounds
    static let amberGlow = Color(red: 1.0, green: 0.75, blue: 0.25)

    // MARK: - Chassis / surface colors

    /// Main chassis background — dark warm charcoal
    static let chassis = Color(red: 0.10, green: 0.10, blue: 0.11)

    /// Slightly lighter panel surface for cards and sections
    static let panel = Color(red: 0.14, green: 0.14, blue: 0.15)

    /// Button inactive background — dark charcoal
    static let buttonInactive = Color(red: 0.16, green: 0.16, blue: 0.17)

    /// Subtle border/divider color
    static let border = Color(white: 0.25)

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
    static let spectrumFill = Color(red: 0.0, green: 0.25, blue: 0.55).opacity(0.65)

    /// Spectrum outline trace
    static let spectrumOutline = Color(red: 1.0, green: 0.78, blue: 0.30)

    /// Scope grid lines
    static let scopeGrid = Color(white: 0.18)

    /// Scope background
    static let scopeBackground = Color(red: 0.02, green: 0.02, blue: 0.04)

    /// Frequency axis text
    static let scopeFreqText = Color(red: 0.55, green: 0.55, blue: 0.50)

    /// Center marker on scope
    static let scopeCenterMarker = Color(red: 1.0, green: 0.75, blue: 0.25).opacity(0.5)

    // MARK: - Inline meter bar colors

    /// S-meter bar
    static let barS = Color(red: 0.20, green: 0.75, blue: 0.30)

    /// Power bar
    static let barPower = amberGlow

    /// SWR bar
    static let barSWR = Color(red: 1.0, green: 0.55, blue: 0.15)

    /// ALC bar
    static let barALC = Color(red: 0.95, green: 0.20, blue: 0.15)

    /// Bar background trough
    static let barBackground = Color(white: 0.12)

    // MARK: - TX/RX indicator

    /// TX active (transmitting)
    static let txRed = Color(red: 0.95, green: 0.15, blue: 0.10)

    /// RX idle dot
    static let rxIdle = Color(white: 0.20)

    // MARK: - Text

    /// Secondary label text (row headers, meter labels)
    static let labelSecondary = Color(white: 0.55)

    // MARK: - Animation

    /// Spring for meter needle sweep — mimics a real analog movement
    static let needleSpring = Animation.interpolatingSpring(
        mass: 0.4, stiffness: 80, damping: 8, initialVelocity: 0
    )
}

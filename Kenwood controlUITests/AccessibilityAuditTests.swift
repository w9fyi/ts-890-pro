//
//  AccessibilityAuditTests.swift
//  Kenwood controlUITests
//
//  Automated accessibility audit — runs on every CI build.
//  Catches missing labels, insufficient contrast, tiny hit regions, and trait errors.
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launch()
    }

    /// Full audit of the main window with all default categories.
    func testMainWindowAccessibility() throws {
        var issues: [String] = []
        try app.performAccessibilityAudit { issue in
            issues.append("[\(issue.auditType)] \(issue.element?.label ?? "(no label)") — \(issue.compactDescription)")
            return true  // suppress so audit continues and we collect all issues
        }
        XCTAssert(issues.isEmpty, "Accessibility issues found:\n" + issues.joined(separator: "\n"))
    }

    /// Audit specifically for element description quality.
    func testElementDescriptions() throws {
        var issues: [String] = []
        try app.performAccessibilityAudit(for: .sufficientElementDescription) { issue in
            issues.append("[\(issue.auditType)] \(issue.element?.label ?? "(no label)") — \(issue.compactDescription)")
            return true  // suppress so audit continues and we collect all issues
        }
        XCTAssert(issues.isEmpty, "Element description issues found:\n" + issues.joined(separator: "\n"))
    }

    /// Audit hit regions — all interactive elements must be large enough to tap.
    func testHitRegions() throws {
        try app.performAccessibilityAudit(for: .hitRegion)
    }

    /// Open the Operator Audio Settings sheet and audit its contents.
    func testOperatorAudioSettingsSheetAccessibility() throws {
        let audioButton = app.buttons["Operator Audio Settings"]
        XCTAssertTrue(audioButton.waitForExistence(timeout: 5),
                      "Operator Audio Settings button must exist in the TX row")
        audioButton.click()

        let sheetHeading = app.staticTexts["Audio"]
        XCTAssertTrue(sheetHeading.waitForExistence(timeout: 5),
                      "Audio sheet heading must appear after opening Operator Audio Settings")

        var issues: [String] = []
        try app.performAccessibilityAudit { issue in
            issues.append("[\(issue.auditType)] \(issue.element?.label ?? "(no label)") — \(issue.compactDescription)")
            return true  // suppress so audit continues and we collect all issues
        }
        XCTAssert(issues.isEmpty, "Sheet accessibility issues found:\n" + issues.joined(separator: "\n"))
    }

    /// Audit element descriptions inside the Operator Audio Settings sheet.
    func testOperatorAudioSettingsSheetElementDescriptions() throws {
        let audioButton = app.buttons["Operator Audio Settings"]
        XCTAssertTrue(audioButton.waitForExistence(timeout: 5),
                      "Operator Audio Settings button must exist in the TX row")
        audioButton.click()

        let sheetHeading = app.staticTexts["Audio"]
        XCTAssertTrue(sheetHeading.waitForExistence(timeout: 5),
                      "Audio sheet heading must appear after opening Operator Audio Settings")

        var issues: [String] = []
        try app.performAccessibilityAudit(for: .sufficientElementDescription) { issue in
            issues.append("[\(issue.auditType)] \(issue.element?.label ?? "(no label)") — \(issue.compactDescription)")
            return true  // suppress so audit continues and we collect all issues
        }
        XCTAssert(issues.isEmpty, "Sheet element description issues found:\n" + issues.joined(separator: "\n"))
    }
}

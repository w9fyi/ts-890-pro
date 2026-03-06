import XCTest
@testable import Kenwood_control

final class SerialPortTests: XCTestCase {

    // MARK: - isLikelyRadio — positive cases

    func testIsLikelyRadio_cp210x_inName() {
        let port = SerialPort(path: "/dev/cu.usb0", name: "CP2102N USB to UART")
        XCTAssertTrue(port.isLikelyRadio)
    }

    func testIsLikelyRadio_silicon_inName() {
        let port = SerialPort(path: "/dev/cu.usb0", name: "Silicon Labs USB")
        XCTAssertTrue(port.isLikelyRadio)
    }

    func testIsLikelyRadio_ftdi_inName() {
        let port = SerialPort(path: "/dev/cu.usb0", name: "FTDI FT232R")
        XCTAssertTrue(port.isLikelyRadio)
    }

    func testIsLikelyRadio_uart_inName() {
        let port = SerialPort(path: "/dev/cu.usb0", name: "USB to UART Bridge")
        XCTAssertTrue(port.isLikelyRadio)
    }

    func testIsLikelyRadio_slab_inPath() {
        // TS-890S CP2102N creates cu.SLAB_USBtoUART
        let port = SerialPort(path: "/dev/cu.SLAB_USBtoUART", name: "Unknown Device")
        XCTAssertTrue(port.isLikelyRadio)
    }

    func testIsLikelyRadio_usbserial_inPath() {
        let port = SerialPort(path: "/dev/cu.usbserial-1cc2f15a", name: "Unknown")
        XCTAssertTrue(port.isLikelyRadio)
    }

    func testIsLikelyRadio_caseInsensitive() {
        // Detection uses .lowercased() — uppercase variants must also match
        let port = SerialPort(path: "/dev/cu.usb0", name: "SILICON LABS CP2102N")
        XCTAssertTrue(port.isLikelyRadio)
    }

    // MARK: - isLikelyRadio — negative cases

    func testIsLikelyRadio_bluetoothDevice_isFalse() {
        let port = SerialPort(path: "/dev/cu.Bluetooth-Incoming-Port", name: "Bluetooth")
        XCTAssertFalse(port.isLikelyRadio)
    }

    func testIsLikelyRadio_genericDevice_isFalse() {
        let port = SerialPort(path: "/dev/cu.debug-console", name: "Debug Console")
        XCTAssertFalse(port.isLikelyRadio)
    }

    func testIsLikelyRadio_wwan_isFalse() {
        let port = SerialPort(path: "/dev/cu.wlan0", name: "WWAN Modem")
        XCTAssertFalse(port.isLikelyRadio)
    }

    // MARK: - displayName

    func testDisplayName_containsNameAndPath() {
        let port = SerialPort(path: "/dev/cu.SLAB_USBtoUART", name: "CP2102N USB to UART")
        XCTAssertTrue(port.displayName.contains("CP2102N USB to UART"))
        XCTAssertTrue(port.displayName.contains("/dev/cu.SLAB_USBtoUART"))
    }

    // MARK: - id

    func testId_equalsPath() {
        let port = SerialPort(path: "/dev/cu.usbserial-abc", name: "Test")
        XCTAssertEqual(port.id, "/dev/cu.usbserial-abc")
    }

    // MARK: - Hashable / Equatable

    func testHashable_samePathAndName_areEqual() {
        let a = SerialPort(path: "/dev/cu.SLAB_USBtoUART", name: "CP2102N")
        let b = SerialPort(path: "/dev/cu.SLAB_USBtoUART", name: "CP2102N")
        XCTAssertEqual(a, b)
    }

    func testHashable_differentPath_areNotEqual() {
        let a = SerialPort(path: "/dev/cu.SLAB_USBtoUART",  name: "CP2102N")
        let b = SerialPort(path: "/dev/cu.SLAB_USBtoUART7", name: "CP2102N")
        XCTAssertNotEqual(a, b)
    }

    func testHashable_canBeUsedInSet() {
        let a = SerialPort(path: "/dev/cu.SLAB_USBtoUART", name: "CP2102N")
        let b = SerialPort(path: "/dev/cu.SLAB_USBtoUART", name: "CP2102N")
        let set: Set<SerialPort> = [a, b]
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - availablePorts smoke test

    func testAvailablePorts_doesNotCrash() {
        // No hardware required — just verify it returns without throwing or crashing.
        let ports = SerialPortScanner.availablePorts()
        XCTAssertNotNil(ports)
    }

    func testAvailablePorts_radioLikelyDevicesSortedFirst() {
        // If any radio-likely ports are present, they must all appear before non-radio ports.
        let ports = SerialPortScanner.availablePorts()
        guard ports.count > 1 else { return }  // nothing to assert with 0 or 1 port

        var seenNonRadio = false
        for port in ports {
            if !port.isLikelyRadio {
                seenNonRadio = true
            } else if seenNonRadio {
                XCTFail("Radio-likely port \(port.path) appeared after a non-radio port — sort order is wrong")
            }
        }
    }
}

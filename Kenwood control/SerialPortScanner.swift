import Foundation
import IOKit
import IOKit.serial

// MARK: - SerialPort model

struct SerialPort: Identifiable, Hashable {
    var id: String { path }
    let path: String    // e.g. /dev/cu.usbserial-1cc2f15a…
    let name: String    // human-readable label

    /// True for devices that are likely a radio USB-serial adapter (CP210x, FTDI, etc.)
    var isLikelyRadio: Bool {
        let lower = name.lowercased() + path.lowercased()
        return lower.contains("cp210") || lower.contains("silicon") ||
               lower.contains("ftdi")  || lower.contains("usbserial") ||
               lower.contains("uart")  || lower.contains("slab")
    }

    var displayName: String { "\(name)  —  \(path)" }
}

// MARK: - Scanner

enum SerialPortScanner {
    /// Returns all available cu.* serial callout ports, radio-likely devices sorted first.
    static func availablePorts() -> [SerialPort] {
        var ports: [SerialPort] = []

        guard let matchDict = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            // Use the callout (cu.*) path — correct for initiating connections
            guard
                let calloutCF = IORegistryEntryCreateCFProperty(
                    service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0),
                let path = calloutCF.takeRetainedValue() as? String
            else { continue }

            let name = usbProductName(for: service)
                    ?? ttyDeviceName(for: service)
                    ?? URL(fileURLWithPath: path).lastPathComponent

            ports.append(SerialPort(path: path, name: name))
        }

        return ports.sorted { a, b in
            if a.isLikelyRadio != b.isLikelyRadio { return a.isLikelyRadio }
            return a.path < b.path
        }
    }

    // MARK: - Private helpers

    private static func ttyDeviceName(for service: io_service_t) -> String? {
        guard let cf = IORegistryEntryCreateCFProperty(
            service, "IOTTYDeviceName" as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        return cf.takeRetainedValue() as? String
    }

    /// Walk up the IOKit registry tree to find the USB product string.
    private static func usbProductName(for service: io_service_t) -> String? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<6 {
            for key in ["USB Product Name", "Product Name", "kUSBProductString"] {
                if let cf = IORegistryEntryCreateCFProperty(
                    current, key as CFString, kCFAllocatorDefault, 0),
                   let name = cf.takeRetainedValue() as? String,
                   !name.isEmpty
                {
                    return name
                }
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != 0 else { break }
            IOObjectRelease(current)
            current = parent
        }
        return nil
    }
}

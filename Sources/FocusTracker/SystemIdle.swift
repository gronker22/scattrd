import Foundation
import IOKit

/// Seconds since the last user input (keyboard or mouse), read from the
/// IOHIDSystem registry. This is the robust, permission-free way to detect
/// "away from keyboard" — no Accessibility grant required.
enum SystemIdle {
    static func seconds() -> Double {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDSystem")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let idle = dict["HIDIdleTime"] as? NSNumber else {
            return 0
        }
        // HIDIdleTime is in nanoseconds.
        return idle.doubleValue / 1_000_000_000.0
    }
}

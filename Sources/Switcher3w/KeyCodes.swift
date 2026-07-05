import Foundation

/// macOS virtual key codes used when parsing input and simulating key presses.
/// Previously scattered across the code as "magic" numbers.
enum KC {
    static let letterC: UInt16 = 8   // Cmd+C — copy
    static let letterV: UInt16 = 9   // Cmd+V — paste
    static let enter: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let backspace: UInt16 = 51
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126

    // Modifiers (for the configurable trigger; we distinguish left/right)
    static let rightCommand: UInt16 = 54
    static let leftCommand: UInt16 = 55
    static let leftShift: UInt16 = 56
    static let capsLock: UInt16 = 57
    static let leftOption: UInt16 = 58
    static let leftControl: UInt16 = 59
    static let rightShift: UInt16 = 60
    static let rightOption: UInt16 = 61
    static let rightControl: UInt16 = 62
}

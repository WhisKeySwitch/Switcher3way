import Foundation

/// Виртуальные коды клавиш (macOS virtual key codes), используемые при разборе
/// ввода и симуляции нажатий. Раньше были разбросаны по коду «магическими» числами.
enum KC {
    static let letterC: UInt16 = 8   // Cmd+C — копировать
    static let letterV: UInt16 = 9   // Cmd+V — вставить
    static let enter: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let backspace: UInt16 = 51
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126

    // Модификаторы (для конфигурируемого триггера; различаем лево/право)
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

import Foundation
#if os(macOS)
import CoreGraphics
#endif

/// Maps platform key codes to USB HID key codes.
///
/// Reference: USB HID Usage Tables 1.4, Section 10 (Keyboard/Keypad Page 0x07)
enum KeyMapping {
    // MARK: - USB HID Modifier Flags
    static let modLeftControl:  UInt8 = 0x01
    static let modLeftShift:    UInt8 = 0x02
    static let modLeftAlt:      UInt8 = 0x04
    static let modLeftGUI:      UInt8 = 0x08  // Command on macOS
    static let modRightControl: UInt8 = 0x10
    static let modRightShift:   UInt8 = 0x20
    static let modRightAlt:     UInt8 = 0x40
    static let modRightGUI:     UInt8 = 0x80

    // MARK: - USB HID Key Codes

    /// Map macOS virtual key code → USB HID usage ID.
    /// macOS key codes from Carbon Events (kVK_* constants).
    static let macOSToHID: [UInt16: UInt8] = [
        // Letters (kVK_ANSI_A = 0x00, etc.)
        0x00: 0x04, // A
        0x0B: 0x05, // B
        0x08: 0x06, // C
        0x02: 0x07, // D
        0x0E: 0x08, // E
        0x03: 0x09, // F
        0x05: 0x0A, // G
        0x04: 0x0B, // H
        0x22: 0x0C, // I
        0x26: 0x0D, // J
        0x28: 0x0E, // K
        0x25: 0x0F, // L
        0x2E: 0x10, // M
        0x2D: 0x11, // N
        0x1F: 0x12, // O
        0x23: 0x13, // P
        0x0C: 0x14, // Q
        0x0F: 0x15, // R
        0x01: 0x16, // S
        0x11: 0x17, // T
        0x20: 0x18, // U
        0x09: 0x19, // V
        0x0D: 0x1A, // W
        0x07: 0x1B, // X
        0x10: 0x1C, // Y
        0x06: 0x1D, // Z

        // Numbers (kVK_ANSI_0 = 0x1D, kVK_ANSI_1 = 0x12, etc.)
        0x12: 0x1E, // 1
        0x13: 0x1F, // 2
        0x14: 0x20, // 3
        0x15: 0x21, // 4
        0x17: 0x22, // 5
        0x16: 0x23, // 6
        0x1A: 0x24, // 7
        0x1C: 0x25, // 8
        0x19: 0x26, // 9
        0x1D: 0x27, // 0

        // Special keys
        0x24: 0x28, // Return
        0x35: 0x29, // Escape
        0x33: 0x2A, // Backspace (Delete)
        0x30: 0x2B, // Tab
        0x31: 0x2C, // Space

        // Punctuation
        0x1B: 0x2D, // Minus -
        0x18: 0x2E, // Equals =
        0x21: 0x2F, // Left bracket [
        0x1E: 0x30, // Right bracket ]
        0x2A: 0x31, // Backslash
        0x29: 0x33, // Semicolon ;
        0x27: 0x34, // Quote '
        0x32: 0x35, // Grave accent `
        0x2B: 0x36, // Comma ,
        0x2F: 0x37, // Period .
        0x2C: 0x38, // Slash /

        // Function keys
        0x7A: 0x3A, // F1
        0x78: 0x3B, // F2
        0x63: 0x3C, // F3
        0x76: 0x3D, // F4
        0x60: 0x3E, // F5
        0x61: 0x3F, // F6
        0x62: 0x40, // F7
        0x64: 0x41, // F8
        0x65: 0x42, // F9
        0x6D: 0x43, // F10
        0x67: 0x44, // F11
        0x6F: 0x45, // F12

        // Navigation
        0x73: 0x4A, // Home
        0x77: 0x4D, // End
        0x74: 0x4B, // Page Up
        0x79: 0x4E, // Page Down
        0x7B: 0x50, // Left Arrow
        0x7C: 0x4F, // Right Arrow
        0x7E: 0x52, // Up Arrow
        0x7D: 0x51, // Down Arrow

        // Editing
        0x72: 0x49, // Insert (Help on Mac)
        0x75: 0x4C, // Forward Delete

        // Lock keys
        0x39: 0x39, // Caps Lock

        // Modifier keys (not usually sent as key reports, but mapping exists)
        0x3B: 0xE0, // Left Control
        0x38: 0xE1, // Left Shift
        0x3A: 0xE2, // Left Option/Alt
        0x37: 0xE3, // Left Command/GUI
        0x3E: 0xE5, // Right Shift
        0x3D: 0xE6, // Right Option/Alt
        0x36: 0xE7, // Right Command/GUI
    ]

    #if os(iOS)
    /// Map UIKit key HID usage codes (UIKeyboardHIDUsage) directly.
    /// On iPad, UIKey.keyCode is already a HID usage, so mapping is mostly identity.
    static func hidKeyFromUIKeyCode(_ keyCode: Int) -> UInt8? {
        guard keyCode > 0 && keyCode < 256 else { return nil }
        return UInt8(keyCode)
    }
    #endif

    /// Get the HID modifier byte from macOS modifier flags.
    #if os(macOS)
    static func modifierByteFromNSEventFlags(_ flags: UInt) -> UInt8 {
        var modifier: UInt8 = 0
        if flags & (1 << 18) != 0 { modifier |= modLeftControl }  // NSEvent.ModifierFlags.control
        if flags & (1 << 17) != 0 { modifier |= modLeftShift }    // NSEvent.ModifierFlags.shift
        if flags & (1 << 19) != 0 { modifier |= modLeftAlt }      // NSEvent.ModifierFlags.option
        if flags & (1 << 20) != 0 { modifier |= modLeftGUI }      // NSEvent.ModifierFlags.command
        return modifier
    }

    static func modifierByteFromCGEventFlags(_ flags: UInt64) -> UInt8 {
        var modifier: UInt8 = 0
        if flags & UInt64(CGEventFlags.maskControl.rawValue) != 0 { modifier |= modLeftControl }
        if flags & UInt64(CGEventFlags.maskShift.rawValue) != 0   { modifier |= modLeftShift }
        if flags & UInt64(CGEventFlags.maskAlternate.rawValue) != 0 { modifier |= modLeftAlt }
        if flags & UInt64(CGEventFlags.maskCommand.rawValue) != 0 { modifier |= modLeftGUI }
        return modifier
    }
    #endif

    // MARK: - Mouse Buttons (USB HID)
    static let mouseButtonLeft:   UInt8 = 0x01
    static let mouseButtonRight:  UInt8 = 0x02
    static let mouseButtonMiddle: UInt8 = 0x04
}

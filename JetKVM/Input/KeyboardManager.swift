import Foundation
import os

#if os(macOS)
import AppKit
import CoreGraphics

/// Captures keyboard events on macOS.
///
/// Uses a CGEvent tap when Accessibility permissions are granted, which
/// intercepts all keyboard events including system shortcuts (Cmd+Space,
/// Cmd+Tab, etc.). Falls back to NSEvent local monitor if permissions
/// are not yet granted.
@MainActor
final class KeyboardManager {
    private let logger = Logger(subsystem: "com.jetkvm.app", category: "Keyboard")
    private var hidService: HIDService?
    private var isCapturing = false

    // CGEvent tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Fallback NSEvent monitor
    private var localMonitor: Any?

    // Track currently pressed keys for full keyboard report
    private var pressedKeys: Set<UInt8> = []
    private var currentModifiers: UInt8 = 0

    /// Whether keyboard capture is currently suspended (e.g. dialog open)
    var isCaptureSuspended = false

    /// Whether the app window is focused — only intercept when true
    var isWindowFocused = true

    /// Whether we have Accessibility permissions
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user for Accessibility permissions
    nonisolated static func requestAccessibilityPermission() {
        // "AXTrustedCheckOptionPrompt" is the raw key behind kAXTrustedCheckOptionPrompt
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func attach(to hidService: HIDService) {
        self.hidService = hidService
    }

    func startCapturing() {
        guard !isCapturing else { return }

        if Self.hasAccessibilityPermission {
            startCGEventTap()
        } else {
            startLocalMonitor()
        }

        isCapturing = true
    }

    func stopCapturing() {
        stopCGEventTap()
        stopLocalMonitor()

        isCapturing = false
        pressedKeys.removeAll()
        currentModifiers = 0
        hidService?.sendKeyboardReport(modifier: 0, keys: [])
        logger.info("Keyboard capture stopped")
    }

    // MARK: - CGEvent Tap (captures system shortcuts)

    private func startCGEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        // Store self as a pointer for the C callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardManager>.fromOpaque(refcon).takeUnretainedValue()

                // If tap is disabled by the system, re-enable it
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Only intercept when our window is focused and capture not suspended
                guard manager.isWindowFocused && !manager.isCaptureSuspended else {
                    return Unmanaged.passUnretained(event)
                }

                // Process on main thread and suppress the event
                DispatchQueue.main.async {
                    manager.handleCGEvent(type: type, event: event)
                }
                return nil // Suppress the event
            },
            userInfo: selfPtr
        ) else {
            logger.warning("Failed to create CGEvent tap — falling back to NSEvent monitor")
            startLocalMonitor()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("CGEvent tap started — capturing system shortcuts")
    }

    private func stopCGEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged {
            let rawFlags = event.flags.rawValue
            currentModifiers = KeyMapping.modifierByteFromCGEventFlags(rawFlags)
            sendFullReport()
            return
        }

        guard let hidKey = KeyMapping.macOSToHID[keyCode] else {
            logger.debug("Unmapped key: \(keyCode)")
            return
        }

        if hidKey >= 0xE0 { return }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat {
                pressedKeys.insert(hidKey)
            }
        } else if type == .keyUp {
            pressedKeys.remove(hidKey)
        }
        sendFullReport()
    }

    // MARK: - NSEvent Local Monitor (fallback)

    private func startLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, !self.isCaptureSuspended else { return event }
            self.handleNSEvent(event)
            return nil
        }
        logger.info("NSEvent monitor started (no Accessibility permission)")
    }

    private func stopLocalMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        let keyCode = event.keyCode

        if event.type == .flagsChanged {
            currentModifiers = KeyMapping.modifierByteFromNSEventFlags(event.modifierFlags.rawValue)
            sendFullReport()
            return
        }

        guard let hidKey = KeyMapping.macOSToHID[keyCode] else {
            logger.debug("Unmapped key: \(keyCode)")
            return
        }

        if hidKey >= 0xE0 { return }

        if event.type == .keyDown {
            if !event.isARepeat {
                pressedKeys.insert(hidKey)
            }
        } else if event.type == .keyUp {
            pressedKeys.remove(hidKey)
        }
        sendFullReport()
    }

    // MARK: - HID Report

    private func sendFullReport() {
        let keys = Array(pressedKeys.prefix(6))
        hidService?.sendKeyboardReport(modifier: currentModifiers, keys: keys)
    }
}
#endif

#if os(iOS)
import UIKit

/// Captures keyboard events on iPad using UIKit responder chain.
@MainActor
final class KeyboardManager {
    private let logger = Logger(subsystem: "com.jetkvm.app", category: "Keyboard")
    private(set) var hidService: HIDService?
    private var isCapturing = false

    /// Whether keyboard capture is currently suspended (e.g. dialog open)
    var isCaptureSuspended = false

    private var pressedKeys: Set<UInt8> = []
    private var currentModifiers: UInt8 = 0

    func attach(to hidService: HIDService) {
        self.hidService = hidService
    }

    func startCapturing() {
        isCapturing = true
        logger.info("Keyboard capture started (iPad)")
    }

    func stopCapturing() {
        isCapturing = false
        pressedKeys.removeAll()
        currentModifiers = 0
        hidService?.sendKeyboardReport(modifier: 0, keys: [])
        logger.info("Keyboard capture stopped (iPad)")
    }

    /// Called from the UIKit responder handling key presses.
    func handleKeyDown(_ press: UIPress) {
        guard isCapturing, !isCaptureSuspended, let key = press.key else { return }

        // Update modifiers
        currentModifiers = modifierByte(from: key.modifierFlags)

        // UIKey.keyCode is already a HID usage code
        if let hidKey = KeyMapping.hidKeyFromUIKeyCode(key.keyCode.rawValue) {
            if hidKey < 0xE0 {
                pressedKeys.insert(hidKey)
            }
        }
        sendFullReport()
    }

    func handleKeyUp(_ press: UIPress) {
        guard isCapturing, !isCaptureSuspended, let key = press.key else { return }

        currentModifiers = modifierByte(from: key.modifierFlags)

        if let hidKey = KeyMapping.hidKeyFromUIKeyCode(key.keyCode.rawValue) {
            if hidKey < 0xE0 {
                pressedKeys.remove(hidKey)
            }
        }
        sendFullReport()
    }

    private func sendFullReport() {
        let keys = Array(pressedKeys.prefix(6))
        hidService?.sendKeyboardReport(modifier: currentModifiers, keys: keys)
    }

    func modifierByte(from flags: UIKeyModifierFlags) -> UInt8 {
        var modifier: UInt8 = 0
        if flags.contains(.control) { modifier |= KeyMapping.modLeftControl }
        if flags.contains(.shift) { modifier |= KeyMapping.modLeftShift }
        if flags.contains(.alternate) { modifier |= KeyMapping.modLeftAlt }
        if flags.contains(.command) { modifier |= KeyMapping.modLeftGUI }
        return modifier
    }
}
#endif

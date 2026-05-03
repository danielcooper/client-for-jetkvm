import SwiftUI
import os

#if os(macOS)
import AppKit

/// A transparent NSView overlay that captures all mouse events for KVM input.
/// Uses NSTrackingArea for hover tracking and overrides mouse event methods.
struct InputOverlayView: NSViewRepresentable {
    let mouseManager: MouseManager
    let keyboardManager: KeyboardManager

    func makeNSView(context: Context) -> KVMInputNSView {
        let view = KVMInputNSView()
        view.mouseManager = mouseManager
        view.keyboardManager = keyboardManager
        return view
    }

    func updateNSView(_ view: KVMInputNSView, context: Context) {
        view.mouseManager = mouseManager
        view.keyboardManager = keyboardManager
    }
}

class KVMInputNSView: NSView {
    var mouseManager: MouseManager?
    var keyboardManager: KeyboardManager?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        // Keep MouseManager informed of view bounds
        Task { @MainActor in
            mouseManager?.viewBounds = CGRect(origin: .zero, size: bounds.size)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        true
    }

    // MARK: - Keyboard (handled via NSEvent monitor in KeyboardManager,
    //          but we override here to prevent system beeps for unhandled keys)

    override func keyDown(with event: NSEvent) {
        // Don't call super — that causes the system beep
    }

    override func keyUp(with event: NSEvent) {
        // Don't call super
    }

    // MARK: - Mouse Movement

    override func mouseMoved(with event: NSEvent) {
        sendPosition(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendPosition(from: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendPosition(from: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendPosition(from: event)
    }

    // MARK: - Mouse Buttons

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convertToViewPoint(event)
        Task { @MainActor in
            mouseManager?.mouseDown(button: .left, at: point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convertToViewPoint(event)
        Task { @MainActor in
            mouseManager?.mouseUp(button: .left, at: point)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convertToViewPoint(event)
        Task { @MainActor in
            mouseManager?.mouseDown(button: .right, at: point)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let point = convertToViewPoint(event)
        Task { @MainActor in
            mouseManager?.mouseUp(button: .right, at: point)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        let point = convertToViewPoint(event)
        Task { @MainActor in
            mouseManager?.mouseDown(button: .middle, at: point)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = convertToViewPoint(event)
        Task { @MainActor in
            mouseManager?.mouseUp(button: .middle, at: point)
        }
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        // Use scrollingDeltaY (continuous trackpad) or deltaY (discrete wheel)
        let dy: CGFloat
        let dx: CGFloat
        if event.hasPreciseScrollingDeltas {
            // Trackpad — scale down the deltas
            dy = -event.scrollingDeltaY / 10.0
            dx = event.scrollingDeltaX / 10.0
        } else {
            // Mouse wheel — use as-is
            dy = -event.scrollingDeltaY
            dx = event.scrollingDeltaX
        }
        Task { @MainActor in
            mouseManager?.scroll(deltaY: dy, deltaX: dx)
        }
    }

    // MARK: - Coordinate Conversion

    private func sendPosition(from event: NSEvent) {
        let point = convertToViewPoint(event)
        Task { @MainActor in
            mouseManager?.sendMousePosition(viewPoint: point)
        }
    }

    /// Convert NSEvent location to view coordinates (origin top-left).
    /// NSView has flipped=false by default, so origin is bottom-left — we flip Y.
    private func convertToViewPoint(_ event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return CGPoint(x: localPoint.x, y: bounds.height - localPoint.y)
    }
}
#endif

#if os(iOS)
import UIKit

/// A transparent UIView overlay that captures all touch/pointer events for KVM input.
struct InputOverlayView: UIViewRepresentable {
    let mouseManager: MouseManager
    let keyboardManager: KeyboardManager
    weak var viewModel: KVMViewModel?

    func makeUIView(context: Context) -> KVMInputUIView {
        let view = KVMInputUIView()
        view.mouseManager = mouseManager
        view.keyboardManager = keyboardManager
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false

        // Enable pointer interaction for iPad mouse/trackpad support
        let pointerInteraction = UIPointerInteraction(delegate: context.coordinator)
        view.addInteraction(pointerInteraction)

        // Hover gesture for trackpad/mouse cursor tracking
        let hover = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHover(_:)))
        view.addGestureRecognizer(hover)

        // Scroll via two-finger pan (trackpad scroll)
        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleScroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.maximumNumberOfTouches = 0 // Only trackpad scroll, not finger pans
        view.addGestureRecognizer(scroll)

        context.coordinator.view = view
        // Register with view model so it can toggle keyboard
        Task { @MainActor in viewModel?.inputView = view }
        return view
    }

    func updateUIView(_ view: KVMInputUIView, context: Context) {
        view.mouseManager = mouseManager
        view.keyboardManager = keyboardManager
        context.coordinator.view = view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIPointerInteractionDelegate {
        weak var view: KVMInputUIView?
        private var lastScrollTranslation: CGPoint = .zero

        @objc func handleHover(_ gesture: UIHoverGestureRecognizer) {
            guard let view = gesture.view as? KVMInputUIView else { return }
            let point = gesture.location(in: view)
            switch gesture.state {
            case .began, .changed:
                Task { @MainActor in
                    view.mouseManager?.sendMousePosition(viewPoint: point)
                }
            default:
                break
            }
        }

        @objc func handleScroll(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? KVMInputUIView else { return }
            switch gesture.state {
            case .began:
                lastScrollTranslation = .zero
            case .changed:
                let translation = gesture.translation(in: view)
                let dx = translation.x - lastScrollTranslation.x
                let dy = translation.y - lastScrollTranslation.y
                lastScrollTranslation = translation
                Task { @MainActor in
                    view.mouseManager?.scroll(deltaY: -dy / 10.0, deltaX: dx / 10.0)
                }
            default:
                lastScrollTranslation = .zero
            }
        }

        func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? {
            return defaultRegion
        }

        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
            // Show a small crosshair so the user can see where they're pointing
            let params = UIPointerShape.roundedRect(CGRect(x: -2, y: -2, width: 4, height: 4), radius: 2)
            return UIPointerStyle(shape: params)
        }
    }
}

class KVMInputUIView: UIView, UIKeyInput {
    var mouseManager: MouseManager?
    var keyboardManager: KeyboardManager?

    // Empty view returned as inputView to suppress the software keyboard
    private let emptyInputView = UIView(frame: .zero)

    var showSoftwareKeyboard = false {
        didSet {
            // Stay first responder always — just toggle the keyboard visibility
            reloadInputViews()
            if !isFirstResponder { becomeFirstResponder() }
        }
    }

    override var canBecomeFirstResponder: Bool { true }

    // Return nil (show keyboard) or empty view (hide keyboard)
    override var inputView: UIView? {
        showSoftwareKeyboard ? nil : emptyInputView
    }

    // UIKeyInput conformance — needed so the system shows the software keyboard
    var hasText: Bool { false }
    func insertText(_ text: String) {
        // Software keyboard typed a character — send as key press + release
        guard let keyboardManager else { return }
        for char in text {
            if let hidKey = hidKeyForCharacter(char) {
                Task { @MainActor in
                    keyboardManager.hidService?.sendKeypress(keycode: hidKey, isDown: true)
                    try? await Task.sleep(for: .milliseconds(20))
                    keyboardManager.hidService?.sendKeypress(keycode: hidKey, isDown: false)
                }
            }
        }
    }
    func deleteBackward() {
        Task { @MainActor in
            keyboardManager?.hidService?.sendKeypress(keycode: 0x2A, isDown: true) // Backspace
            try? await Task.sleep(for: .milliseconds(20))
            keyboardManager?.hidService?.sendKeypress(keycode: 0x2A, isDown: false)
        }
    }

    /// Map a typed character to its USB HID key code (unshifted keys only;
    /// the software keyboard handles shift itself via the text it sends).
    private func hidKeyForCharacter(_ char: Character) -> UInt8? {
        switch char {
        case "a"..."z":
            return UInt8(char.asciiValue! - 0x61 + 0x04) // a=0x04 .. z=0x1D
        case "A"..."Z":
            return UInt8(char.asciiValue! - 0x41 + 0x04)
        case "1": return 0x1E
        case "2": return 0x1F
        case "3": return 0x20
        case "4": return 0x21
        case "5": return 0x22
        case "6": return 0x23
        case "7": return 0x24
        case "8": return 0x25
        case "9": return 0x26
        case "0": return 0x27
        case "\n", "\r": return 0x28 // Return
        case "\t": return 0x2B       // Tab
        case " ": return 0x2C        // Space
        case "-": return 0x2D
        case "=": return 0x2E
        case "[": return 0x2F
        case "]": return 0x30
        case "\\": return 0x31
        case ";": return 0x33
        case "'": return 0x34
        case "`": return 0x35
        case ",": return 0x36
        case ".": return 0x37
        case "/": return 0x38
        default: return nil
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        Task { @MainActor in
            mouseManager?.viewBounds = CGRect(origin: .zero, size: bounds.size)
        }
    }

    // MARK: - Touch Events (for direct touch and trackpad clicks)

    /// Determine button from event — secondary buttonMask = right-click (trackpad)
    private func mouseButton(for event: UIEvent?) -> MouseButton {
        event?.buttonMask.contains(.secondary) == true ? .right : .left
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let button = mouseButton(for: event)
        Task { @MainActor in
            mouseManager?.mouseDown(button: button, at: point)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        Task { @MainActor in
            mouseManager?.sendMousePosition(viewPoint: point)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let button = mouseButton(for: event)
        Task { @MainActor in
            mouseManager?.mouseUp(button: button, at: point)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let button = mouseButton(for: event)
        Task { @MainActor in
            mouseManager?.mouseUp(button: button, at: point)
        }
    }

    // MARK: - Key Commands (claim modifier shortcuts from iPadOS)

    private static let capturedKeyCommands: [UIKeyCommand] = {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let modifiers: [UIKeyModifierFlags] = [.command, .control, .alternate,
                                                [.command, .shift], [.command, .alternate],
                                                [.control, .shift], [.control, .alternate]]
        var commands: [UIKeyCommand] = []
        for mod in modifiers {
            for char in letters {
                let cmd = UIKeyCommand(input: String(char), modifierFlags: mod, action: #selector(handleKeyCommand(_:)))
                cmd.wantsPriorityOverSystemBehavior = true
                commands.append(cmd)
            }
            // Numbers
            for num in 0...9 {
                let cmd = UIKeyCommand(input: "\(num)", modifierFlags: mod, action: #selector(handleKeyCommand(_:)))
                cmd.wantsPriorityOverSystemBehavior = true
                commands.append(cmd)
            }
        }
        // Cmd+Space
        let cmdSpace = UIKeyCommand(input: " ", modifierFlags: .command, action: #selector(handleKeyCommand(_:)))
        cmdSpace.wantsPriorityOverSystemBehavior = true
        commands.append(cmdSpace)
        return commands
    }()

    override var keyCommands: [UIKeyCommand]? {
        Self.capturedKeyCommands
    }

    @objc private func handleKeyCommand(_ command: UIKeyCommand) {
        guard let input = command.input, let keyboardManager else { return }
        // Map the input character to HID keycode
        let hidKey: UInt8?
        if let char = input.first {
            hidKey = hidKeyForCharacter(char)
        } else {
            hidKey = nil
        }
        guard let keycode = hidKey else { return }

        let modifier = keyboardManager.modifierByte(from: command.modifierFlags)
        Task { @MainActor in
            keyboardManager.hidService?.sendKeyboardReport(modifier: modifier, keys: [keycode])
            try? await Task.sleep(for: .milliseconds(30))
            keyboardManager.hidService?.sendKeyboardReport(modifier: 0, keys: [])
        }
    }

    // MARK: - Key Events (iPad hardware keyboard)

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if press.key != nil {
                handled = true
                Task { @MainActor in
                    keyboardManager?.handleKeyDown(press)
                }
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if press.key != nil {
                handled = true
                Task { @MainActor in
                    keyboardManager?.handleKeyUp(press)
                }
            }
        }
        if !handled { super.pressesEnded(presses, with: event) }
    }
}
#endif

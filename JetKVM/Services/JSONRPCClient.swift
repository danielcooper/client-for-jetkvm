import Foundation
import os

/// JSON-RPC 2.0 client over WebRTC DataChannel.
///
/// Used for device management commands (getVideoState, ping, etc.)
/// and as a fallback for input if binary HID isn't available.
@MainActor
final class JSONRPCClient {
    private let logger = Logger(subsystem: "com.jetkvm.app", category: "JSONRPC")
    private weak var webrtcClient: WebRTCClient?
    private var nextID = 1

    init(webrtcClient: WebRTCClient) {
        self.webrtcClient = webrtcClient
    }

    // MARK: - Generic RPC

    func call(method: String, params: [String: Any]? = nil) {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "id": nextID
        ]
        nextID += 1

        if let params {
            message["params"] = params
        }

        guard let data = try? JSONSerialization.data(withJSONObject: message) else {
            logger.error("Failed to serialize RPC: \(method)")
            return
        }

        webrtcClient?.sendRPC(data)
        logger.debug("RPC call: \(method)")
    }

    // MARK: - Input Methods (fallback, prefer HIDService binary protocol)

    func sendKeyboardReport(modifier: UInt8, keys: [UInt8]) {
        let keysArray = Array(keys.prefix(6))
        call(method: "keyboardReport", params: [
            "modifier": modifier,
            "keys": keysArray
        ])
    }

    func sendKeypressReport(key: UInt8, press: Bool) {
        call(method: "keypressReport", params: [
            "key": key,
            "press": press
        ])
    }

    func sendAbsMouseReport(x: Int, y: Int, buttons: UInt8) {
        call(method: "absMouseReport", params: [
            "x": x,
            "y": y,
            "buttons": buttons
        ])
    }

    func sendRelMouseReport(dx: Int8, dy: Int8, buttons: UInt8) {
        call(method: "relMouseReport", params: [
            "dx": dx,
            "dy": dy,
            "buttons": buttons
        ])
    }

    func sendWheelReport(wheelY: Int, wheelX: Int = 0) {
        call(method: "wheelReport", params: [
            "wheelY": wheelY,
            "wheelX": wheelX
        ])
    }

    // MARK: - Device Queries

    func ping() {
        call(method: "ping")
    }

    func getVideoState() {
        call(method: "getVideoState")
    }

    func getUSBState() {
        call(method: "getUSBState")
    }
}

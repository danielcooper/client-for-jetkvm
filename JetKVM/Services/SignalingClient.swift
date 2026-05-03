import Foundation
import os

/// WebSocket signaling client for WebRTC negotiation with JetKVM.
///
/// Protocol:
///   1. Connect to ws://<device>/webrtc/signaling/client
///   2. Receive: {"type":"device-metadata","data":{"deviceVersion":"x.x.x"}}
///   3. Send offer: {"type":"offer","data":{"sd":"<base64(JSON SDP)>"}}
///   4. Receive answer: {"type":"answer","data":"<base64(JSON SDP)>"}
///   5. Exchange ICE candidates: {"type":"new-ice-candidate","data":{...}}
///   6. Keepalive: text "ping" → "pong"
actor SignalingClient {
    private let logger = Logger(subsystem: "com.jetkvm.app", category: "Signaling")
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var keepAliveTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    // Callbacks instead of delegate for Swift 6 actor isolation
    var onDeviceMetadata: (@Sendable (String) -> Void)?
    var onAnswer: (@Sendable (String, String) -> Void)?
    var onICECandidate: (@Sendable (String, String?, Int32) -> Void)?
    var onDisconnect: (@Sendable () -> Void)?

    private(set) var deviceVersion: String?
    private(set) var isConnected = false

    func setCallbacks(
        onDeviceMetadata: (@Sendable (String) -> Void)?,
        onAnswer: (@Sendable (String, String) -> Void)?,
        onICECandidate: (@Sendable (String, String?, Int32) -> Void)?,
        onDisconnect: (@Sendable () -> Void)?
    ) {
        self.onDeviceMetadata = onDeviceMetadata
        self.onAnswer = onAnswer
        self.onICECandidate = onICECandidate
        self.onDisconnect = onDisconnect
    }

    func connect(to device: KVMDevice, cookieHeader: String?) async throws {
        let url = device.webSocketURL
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        let session = URLSession(configuration: config)
        self.session = session

        var request = URLRequest(url: url)
        if let cookies = cookieHeader {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
        }

        let ws = session.webSocketTask(with: request)
        self.webSocket = ws
        ws.resume()

        isConnected = true
        logger.info("WebSocket connected to \(url)")

        startReceiving()
        startKeepAlive()
    }

    func disconnect() {
        keepAliveTask?.cancel()
        receiveTask?.cancel()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session = nil
        isConnected = false
        deviceVersion = nil
    }

    // MARK: - Send

    /// Send the SDP offer. The `encodedSDP` should already be base64(JSON({type, sdp})).
    func sendOffer(encodedSDP: String) async throws {
        let message: [String: Any] = [
            "type": "offer",
            "data": ["sd": encodedSDP]
        ]

        try await sendJSON(message)
        logger.info("Sent WebRTC offer")
    }

    func sendICECandidate(_ candidate: [String: Any]) async throws {
        let message: [String: Any] = [
            "type": "new-ice-candidate",
            "data": candidate
        ]
        try await sendJSON(message)
    }

    // MARK: - Private

    private func sendJSON(_ dict: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let string = String(data: data, encoding: .utf8)!
        try await webSocket?.send(.string(string))
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let ws = await self.webSocket else { break }
                    let message = try await ws.receive()
                    await self.handleMessage(message)
                } catch {
                    await self.logger.error("WebSocket receive error: \(error)")
                    await self.handleDisconnect()
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            if text == "pong" { return }
            await parseSignalingMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                await parseSignalingMessage(text)
            }
        @unknown default:
            break
        }
    }

    private nonisolated func parseSignalingMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "device-metadata":
            if let metadata = json["data"] as? [String: Any],
               let version = metadata["deviceVersion"] as? String {
                await setDeviceVersion(version)
                await self.onDeviceMetadata?(version)
            }

        case "answer":
            if let answerB64 = json["data"] as? String,
               let answerData = Data(base64Encoded: answerB64),
               let answerJSON = try? JSONSerialization.jsonObject(with: answerData) as? [String: Any] {
                let sdp = answerJSON["sdp"] as? String ?? ""
                let sdpType = answerJSON["type"] as? String ?? "answer"
                await self.onAnswer?(sdp, sdpType)
            }

        case "new-ice-candidate":
            if let candidateData = json["data"] as? [String: Any] {
                let candidate = candidateData["candidate"] as? String ?? ""
                let sdpMid = candidateData["sdpMid"] as? String
                let sdpMLineIndex = candidateData["sdpMLineIndex"] as? Int32 ?? 0
                await self.onICECandidate?(candidate, sdpMid, sdpMLineIndex)
            }

        default:
            break
        }
    }

    private func setDeviceVersion(_ version: String) {
        self.deviceVersion = version
        logger.info("Device version: \(version)")
    }

    private func startKeepAlive() {
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                try? await self?.webSocket?.send(.string("ping"))
            }
        }
    }

    private func handleDisconnect() {
        isConnected = false
        onDisconnect?()
    }
}

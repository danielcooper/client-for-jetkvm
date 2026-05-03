import Foundation
import os

/// Handles authentication with a JetKVM device's REST API.
actor AuthService {
    private let logger = Logger(subsystem: "com.jetkvm.app", category: "Auth")
    private let session: URLSession

    private(set) var authToken: String?
    private(set) var isAuthenticated = false

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    /// Check if the device requires authentication.
    func checkDeviceStatus(device: KVMDevice) async throws -> DeviceStatus {
        let url = device.baseURL.appendingPathComponent("device/status")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.networkError("Failed to check device status")
        }

        return try JSONDecoder().decode(DeviceStatus.self, from: data)
    }

    /// Get device info (auth mode, device ID).
    func getDeviceInfo(device: KVMDevice) async throws -> DeviceInfo {
        let url = device.baseURL.appendingPathComponent("device")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.networkError("Failed to get device info")
        }

        return try JSONDecoder().decode(DeviceInfo.self, from: data)
    }

    /// Authenticate with a password. Returns true if the device uses noPassword mode.
    func login(device: KVMDevice, password: String) async throws {
        let url = device.baseURL.appendingPathComponent("auth/login-local")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            // Extract auth token from cookies
            if let cookies = HTTPCookieStorage.shared.cookies(for: device.baseURL) {
                authToken = cookies.first(where: { $0.name == "authToken" })?.value
            }
            isAuthenticated = true
            logger.info("Login successful for \(device.host)")
        case 401:
            throw AuthError.invalidPassword
        case 403:
            throw AuthError.forbidden
        default:
            throw AuthError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    /// Get cookies formatted for WebSocket connection.
    func cookieHeader(for url: URL) -> String? {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return nil }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func logout() {
        authToken = nil
        isAuthenticated = false
    }
}

enum AuthError: LocalizedError {
    case invalidPassword
    case forbidden
    case networkError(String)
    case deviceNotSetup

    var errorDescription: String? {
        switch self {
        case .invalidPassword: "Invalid password"
        case .forbidden: "Access forbidden"
        case .networkError(let msg): "Network error: \(msg)"
        case .deviceNotSetup: "Device is not set up"
        }
    }
}

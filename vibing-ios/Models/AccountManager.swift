//
//  AccountManager.swift
//  Vibing (iOS)
//
//  账号体系和设备管理 - 对接 Relay Server
//

import Foundation
import Security
import UIKit

// MARK: - Data Models

struct DeviceInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let device_type: String
    let platform: String?
    let registered_at: String?
    let last_seen: String?
    let is_online: Bool

    var displayType: String {
        switch device_type {
        case "mac": return "Mac"
        case "ios": return "iPhone/iPad"
        case "android": return "Android"
        case "web": return "Web"
        default: return device_type
        }
    }

    var typeIcon: String {
        switch device_type {
        case "mac": return "desktopcomputer"
        case "ios": return "iphone"
        case "android": return "smartphone"
        case "web": return "globe"
        default: return "display"
        }
    }
}

struct AuthResponse: Codable {
    let token: String
    let user_id: String
    let username: String
    let device_id: String?
}

struct UserInfo: Codable {
    let user_id: String
    let username: String
    let created_at: String
    let last_login: String?
}

// MARK: - Account Manager

class AccountManager {

    static let shared = AccountManager()

    private(set) var accountId: String?
    private(set) var username: String?
    private(set) var authToken: String?
    private(set) var devices: [DeviceInfo] = []

    var isSignedIn: Bool { authToken != nil && accountId != nil }

    private let apiClient = RelayAPIClient.shared
    private lazy var cachedDeviceId: String = computeDeviceId()

    var onStateChanged: (() -> Void)?

    private init() {
        loadAccount()
    }

    // MARK: - Mock Data (DEBUG)

    func injectMockData() {
        accountId = "vibe_abc12345"
        username = "demo_user"
        authToken = "mock_token"
        devices = [
            DeviceInfo(
                id: "device_macbook_01",
                name: "MacBook Pro (Apple Silicon)",
                device_type: "mac",
                platform: "macOS 15.0",
                registered_at: "2026-03-20T10:00:00Z",
                last_seen: "2026-03-23T16:30:00Z",
                is_online: true
            ),
            DeviceInfo(
                id: "device_imac_02",
                name: "iMac 办公室",
                device_type: "mac",
                platform: "macOS 14.5",
                registered_at: "2026-03-18T08:00:00Z",
                last_seen: "2026-03-23T15:00:00Z",
                is_online: true
            ),
            DeviceInfo(
                id: "device_ipad_03",
                name: "iPad Pro",
                device_type: "ios",
                platform: "iPadOS 18.0",
                registered_at: "2026-03-22T12:00:00Z",
                last_seen: "2026-03-23T14:00:00Z",
                is_online: false
            ),
            DeviceInfo(
                id: "device_web_04",
                name: "Chrome Browser",
                device_type: "web",
                platform: "Web",
                registered_at: "2026-03-21T09:00:00Z",
                last_seen: "2026-03-22T18:00:00Z",
                is_online: false
            ),
        ]
    }

    // MARK: - Registration

    func register(username: String, password: String) async throws {
        let response = try await apiClient.register(
            username: username,
            password: password,
            deviceName: getCurrentDeviceName(),
            deviceType: currentDeviceType()
        )

        authToken = response.token
        accountId = response.user_id
        self.username = response.username
        saveAccount()
        notifyChange()

        try? await fetchDevices()
    }

    // MARK: - Login

    func login(username: String, password: String) async throws {
        let response = try await apiClient.login(
            username: username,
            password: password,
            deviceId: cachedDeviceId,
            deviceName: getCurrentDeviceName(),
            deviceType: currentDeviceType()
        )

        authToken = response.token
        accountId = response.user_id
        self.username = response.username
        saveAccount()
        notifyChange()

        try? await fetchDevices()
    }

    // MARK: - QR Login

    func generateLoginQR() async throws -> UIImage? {
        guard let token = authToken else { return nil }

        let response = try await apiClient.generateQRCode(token: token)
        guard let qrValue = response["qr_code"] as? String else { return nil }

        return generateQRImage(from: qrValue)
    }

    func qrLogin(code: String) async throws {
        let response = try await apiClient.qrLogin(
            code: code,
            deviceId: cachedDeviceId,
            deviceName: getCurrentDeviceName(),
            deviceType: currentDeviceType()
        )

        authToken = response.token
        accountId = response.user_id
        self.username = response.username
        saveAccount()
        notifyChange()

        try? await fetchDevices()
    }

    // MARK: - Logout

    func signOut() {
        authToken = nil
        accountId = nil
        username = nil
        devices.removeAll()

        UserDefaults.standard.removeObject(forKey: "account_id")
        UserDefaults.standard.removeObject(forKey: "account_username")
        TokenKeychain.delete()
        notifyChange()
    }

    // MARK: - Sessions (relay)

    struct RelaySession: Codable {
        let session_id: String
        let device_id: String
        let role: String
        let created_at: String
    }

    func fetchRelaySessions() async throws -> [RelaySession] {
        guard let token = authToken else { return [] }
        return try await apiClient.getRelaySessions(token: token)
    }

    // MARK: - Devices

    func fetchDevices() async throws {
        guard let token = authToken else { return }
        devices = try await apiClient.getDevices(token: token)
        notifyChange()
    }

    func removeDevice(_ deviceId: String) async throws {
        guard let token = authToken else { return }
        try await apiClient.deleteDevice(deviceId: deviceId, token: token)
        devices.removeAll { $0.id == deviceId }
        notifyChange()
    }

    // MARK: - Helpers

    func getDeviceId() -> String { cachedDeviceId }
    func getToken() -> String? { authToken }

    private func currentDeviceType() -> String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ios" : "ios"
    }

    private func computeDeviceId() -> String {
        if let id = UIDevice.current.identifierForVendor?.uuidString {
            return String(id.replacingOccurrences(of: "-", with: "").prefix(16).lowercased())
        }
        // Fallback
        if let saved = UserDefaults.standard.string(forKey: "device_uuid") {
            return saved
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "device_uuid")
        return String(newId.replacingOccurrences(of: "-", with: "").prefix(16).lowercased())
    }

    private func getCurrentDeviceName() -> String {
        let name = UIDevice.current.name
        let model = UIDevice.current.model
        return "\(name) (\(model))"
    }

    private func generateQRImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter?.outputImage else { return nil }

        let scale = CGFloat(10)
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return UIImage(ciImage: transformed)
    }

    // MARK: - Persistence

    private func saveAccount() {
        UserDefaults.standard.set(accountId, forKey: "account_id")
        UserDefaults.standard.set(username, forKey: "account_username")
        if let token = authToken {
            TokenKeychain.save(token: token)
        }
    }

    private func loadAccount() {
        accountId = UserDefaults.standard.string(forKey: "account_id")
        username = UserDefaults.standard.string(forKey: "account_username")
        authToken = TokenKeychain.load()
    }

    private func notifyChange() {
        DispatchQueue.main.async { self.onStateChanged?() }
    }
}

// MARK: - Token Keychain Storage

struct TokenKeychain {
    private static let service = "com.vibing.relay-token"
    private static let account = "auth_token"

    static func save(token: String) {
        guard let data = token.data(using: .utf8) else { return }
        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Relay API Client

class RelayAPIClient {
    static let shared = RelayAPIClient()

    var baseURL: String {
        UserDefaults.standard.string(forKey: "relayServerURL") ?? ""
    }

    private init() {}

    func register(username: String, password: String, deviceName: String, deviceType: String) async throws -> AuthResponse {
        let body: [String: Any] = [
            "username": username, "password": password,
            "device_name": deviceName, "device_type": deviceType,
        ]
        return try await post("/auth/register", body: body, token: nil)
    }

    func login(username: String, password: String, deviceId: String, deviceName: String, deviceType: String) async throws -> AuthResponse {
        let body: [String: Any] = [
            "username": username, "password": password,
            "device_id": deviceId, "device_name": deviceName, "device_type": deviceType,
        ]
        return try await post("/auth/login", body: body, token: nil)
    }

    func generateQRCode(token: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)/auth/qr-generate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AccountError.serverError(parseError(data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AccountError.serverError("Invalid response")
        }
        return json
    }

    func qrLogin(code: String, deviceId: String, deviceName: String, deviceType: String) async throws -> AuthResponse {
        let body: [String: Any] = [
            "code": code, "device_id": deviceId,
            "device_name": deviceName, "device_type": deviceType,
        ]
        return try await post("/auth/qr-login", body: body, token: nil)
    }

    func getUserInfo(token: String) async throws -> UserInfo {
        return try await get("/auth/me", token: token)
    }

    func getDevices(token: String) async throws -> [DeviceInfo] {
        return try await get("/devices", token: token)
    }

    func getRelaySessions(token: String) async throws -> [AccountManager.RelaySession] {
        return try await get("/sessions", token: token)
    }

    func deleteDevice(deviceId: String, token: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/devices/\(deviceId)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AccountError.serverError(parseError(data))
        }
    }

    // MARK: - Helpers

    private func post<T: Codable>(_ path: String, body: [String: Any], token: String?) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AccountError.serverError(parseError(data))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func get<T: Codable>(_ path: String, token: String) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AccountError.serverError(parseError(data))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func parseError(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            return error
        }
        return "Unknown error"
    }
}

// MARK: - Errors

enum AccountError: LocalizedError {
    case notSignedIn
    case networkError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .networkError: return "Network error"
        case .serverError(let msg): return msg
        }
    }
}

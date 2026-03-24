//
//  AccountManager.swift
//  VibeTerminal
//
//  账号体系和设备管理 - 对接 Relay Server
//

import Foundation
import Security
import AppKit
import IOKit

// MARK: - 设备信息

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

// MARK: - 配对状态

enum PairingState {
    case unpaired
    case pairing(String)
    case paired
    case expired
}

// MARK: - 配对请求

struct PairingRequest: Codable, Identifiable {
    var id: String { requestId }
    let requestId: String
    let deviceId: String
    let deviceName: String
    let deviceType: String
    let timestamp: Date
    let expiresAt: Date
    let pairingCode: String
}

// MARK: - 配对响应

struct PairingResponse: Codable {
    let requestId: String
    let approved: Bool
    let serverSignature: Data?
}

// MARK: - Auth Response

struct AuthResponse: Codable {
    let token: String
    let user_id: String
    let username: String
    let device_id: String?
}

// MARK: - User Info

struct UserInfo: Codable {
    let user_id: String
    let username: String
    let created_at: String
    let last_login: String?
}

// MARK: - 账号管理器

class AccountManager: ObservableObject {

    // MARK: - Published Properties

    @Published var accountId: String?
    @Published var username: String?
    @Published var authToken: String?
    @Published var pairingState: PairingState = .unpaired
    @Published var pairingCode: String?
    @Published var pendingRequests: [PairingRequest] = []
    @Published var devices: [DeviceInfo] = []
    @Published var qrCodeImage: NSImage?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isSignedIn: Bool { authToken != nil && accountId != nil }

    // MARK: - Private Properties

    private var pairingTimer: Timer?
    private let apiClient = RelayAPIClient.shared
    private lazy var cachedDeviceId: String = computeDeviceId()

    // MARK: - Singleton

    static let shared = AccountManager()

    private init() {
        loadAccount()
    }

    // MARK: - Registration

    func register(username: String, password: String) async throws {
        await setLoading(true)
        do {
            let deviceName = getCurrentDeviceName()

            let response = try await apiClient.register(
                username: username,
                password: password,
                deviceName: deviceName,
                deviceType: "mac"
            )

            await MainActor.run {
                self.authToken = response.token
                self.accountId = response.user_id
                self.username = response.username
                self.errorMessage = nil
                self.saveAccount()
            }

            try? await fetchDevices()
            await setLoading(false)
        } catch {
            await setLoading(false)
            throw error
        }
    }

    // MARK: - Login

    func login(username: String, password: String) async throws {
        await setLoading(true)
        do {
            let deviceId = getCurrentDeviceId()
            let deviceName = getCurrentDeviceName()

            let response = try await apiClient.login(
                username: username,
                password: password,
                deviceId: deviceId,
                deviceName: deviceName,
                deviceType: "mac"
            )

            await MainActor.run {
                self.authToken = response.token
                self.accountId = response.user_id
                self.username = response.username
                self.errorMessage = nil
                self.saveAccount()
            }

            try? await fetchDevices()
            await setLoading(false)
        } catch {
            await setLoading(false)
            throw error
        }
    }

    // MARK: - Logout

    func signOut() {
        authToken = nil
        accountId = nil
        username = nil
        devices.removeAll()
        pairingState = .unpaired
        errorMessage = nil

        UserDefaults.standard.removeObject(forKey: "account_id")
        UserDefaults.standard.removeObject(forKey: "account_username")
        TokenKeychain.delete()
    }

    // MARK: - Devices

    func fetchDevices() async throws {
        guard let token = authToken else { return }

        let fetchedDevices = try await apiClient.getDevices(token: token)

        await MainActor.run {
            self.devices = fetchedDevices
        }
    }

    func removeDevice(_ deviceId: String) async throws {
        guard let token = authToken else { return }

        try await apiClient.deleteDevice(deviceId: deviceId, token: token)

        await MainActor.run {
            self.devices.removeAll { $0.id == deviceId }
        }
    }

    // MARK: - User Info

    func fetchUserInfo() async throws -> UserInfo? {
        guard let token = authToken else { return nil }
        return try await apiClient.getUserInfo(token: token)
    }

    // MARK: - QR Login

    /// 已登录用户生成 QR 码供其他设备扫码登录
    /// QR 码包含服务器地址 + 登录码，手机扫一次即可完成连接
    /// 格式: vibing://login?server=<url_encoded_server>&code=<url_encoded_code>
    func generateLoginQR() async throws {
        guard let token = authToken else { return }

        let response = try await apiClient.generateQRCode(token: token)
        let qrCode = response["qr_code"] as? String ?? ""

        // 组合服务器地址和登录码
        let serverURL = apiClient.baseURL
        let encodedServer = serverURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? serverURL
        let encodedCode = qrCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? qrCode
        let qrValue = "vibing://login?server=\(encodedServer)&code=\(encodedCode)"

        await MainActor.run {
            self.generateQRCode(from: qrValue)
        }

        // 5 分钟后清除
        pairingTimer?.invalidate()
        pairingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.qrCodeImage = nil
        }
    }

    /// 未登录设备用扫描到的 QR 码登录
    /// 支持两种格式:
    ///   1. vibing://login?server=<url>&code=<code> (新格式，自动设置服务器)
    ///   2. VIBE_QR|<code> (旧格式，使用当前服务器)
    func qrLogin(code: String) async throws {
        await setLoading(true)
        do {
            var loginCode = code

            // 解析 vibing:// URL 格式
            if code.hasPrefix("vibing://login") {
                if let parsed = parseVibingQRURL(code) {
                    // 自动设置服务器地址
                    UserDefaults.standard.set(parsed.server, forKey: "relayServerURL")
                    loginCode = parsed.code
                } else {
                    throw AccountError.invalidPairingCode
                }
            }

            let deviceId = getCurrentDeviceId()
            let deviceName = getCurrentDeviceName()

            let response = try await apiClient.qrLogin(
                code: loginCode,
                deviceId: deviceId,
                deviceName: deviceName,
                deviceType: "mac"
            )

            await MainActor.run {
                self.authToken = response.token
                self.accountId = response.user_id
                self.username = response.username
                self.errorMessage = nil
                self.saveAccount()
            }

            try? await fetchDevices()
            await setLoading(false)
        } catch {
            await setLoading(false)
            throw error
        }
    }

    /// 解析 vibing://login?server=<url>&code=<code> 格式
    private func parseVibingQRURL(_ urlString: String) -> (server: String, code: String)? {
        guard let components = URLComponents(string: urlString),
              components.scheme == "vibing",
              components.host == "login" else { return nil }

        let items = components.queryItems ?? []
        guard let server = items.first(where: { $0.name == "server" })?.value,
              let code = items.first(where: { $0.name == "code" })?.value else { return nil }

        return (server: server, code: code)
    }

    // MARK: - QR Code Generation (Pairing)

    func generatePairingCode() -> String {
        guard let accountId = accountId else { return "" }

        let deviceId = getCurrentDeviceId()
        let timestamp = String(format: "%.0f", Date().timeIntervalSince1970)
        let code = "VT1|\(accountId)|\(deviceId)|\(timestamp)"

        pairingCode = code
        pairingState = .pairing(code)
        generateQRCode(from: code)

        pairingTimer?.invalidate()
        pairingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.pairingState = .expired
            self?.pairingCode = nil
            self?.qrCodeImage = nil
        }

        return code
    }

    private func generateQRCode(from string: String) {
        guard let data = string.data(using: .utf8) else { return }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter?.outputImage else { return }

        let scale = CGFloat(10)
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let rep = NSCIImageRep(ciImage: transformedImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)

        DispatchQueue.main.async {
            self.qrCodeImage = nsImage
        }
    }

    // MARK: - Helpers

    func getDeviceId() -> String {
        cachedDeviceId
    }

    private func getCurrentDeviceId() -> String {
        cachedDeviceId
    }

    private func computeDeviceId() -> String {
        let uuid = getPlatformUUID()
        return String(uuid.replacingOccurrences(of: "-", with: "").prefix(16).lowercased())
    }

    private func getPlatformUUID() -> String {
        let service = IOServiceMatching(kIOPlatformSerialNumberKey)
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, service)

        defer { IOObjectRelease(platformExpert) }

        let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String

        if let serial = serialNumberAsCFString {
            return serial
        }

        if let savedUUID = UserDefaults.standard.string(forKey: "device_uuid") {
            return savedUUID
        }

        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: "device_uuid")
        return newUUID
    }

    private func getCurrentDeviceName() -> String {
        let hostName = Host.current().localizedName ?? "Mac"
        #if arch(arm64)
        return "\(hostName) (Apple Silicon)"
        #else
        return "\(hostName) (Intel)"
        #endif
    }

    // MARK: - Persistence

    private func saveAccount() {
        UserDefaults.standard.set(accountId, forKey: "account_id")
        UserDefaults.standard.set(username, forKey: "account_username")

        // Token 存 Keychain
        if let token = authToken {
            TokenKeychain.save(token: token)
        }
    }

    private func loadAccount() {
        accountId = UserDefaults.standard.string(forKey: "account_id")
        username = UserDefaults.standard.string(forKey: "account_username")
        authToken = TokenKeychain.load()
    }

    @MainActor
    private func setLoading(_ loading: Bool) {
        isLoading = loading
    }
}

// MARK: - Relay API Client

class RelayAPIClient {
    static let shared = RelayAPIClient()

    var baseURL: String {
        UserDefaults.standard.string(forKey: "relayServerURL") ?? "http://127.0.0.1:8766"
    }

    private init() {}

    // MARK: - Auth

    func register(username: String, password: String, deviceName: String, deviceType: String) async throws -> AuthResponse {
        let body: [String: Any] = [
            "username": username,
            "password": password,
            "device_name": deviceName,
            "device_type": deviceType,
        ]
        return try await post("/auth/register", body: body, token: nil)
    }

    func login(username: String, password: String, deviceId: String, deviceName: String, deviceType: String) async throws -> AuthResponse {
        let body: [String: Any] = [
            "username": username,
            "password": password,
            "device_id": deviceId,
            "device_name": deviceName,
            "device_type": deviceType,
        ]
        return try await post("/auth/login", body: body, token: nil)
    }

    func getUserInfo(token: String) async throws -> UserInfo {
        return try await get("/auth/me", token: token)
    }

    // MARK: - QR Login

    func generateQRCode(token: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)/auth/qr-generate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AccountError.serverError(parseError(data))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AccountError.serverError("Invalid response")
        }

        return json
    }

    func qrLogin(code: String, deviceId: String, deviceName: String, deviceType: String) async throws -> AuthResponse {
        let body: [String: Any] = [
            "code": code,
            "device_id": deviceId,
            "device_name": deviceName,
            "device_type": deviceType,
        ]
        return try await post("/auth/qr-login", body: body, token: nil)
    }

    // MARK: - Devices

    func getDevices(token: String) async throws -> [DeviceInfo] {
        return try await get("/devices", token: token)
    }

    func deleteDevice(deviceId: String, token: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/devices/\(deviceId)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountError.networkError
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = parseError(data)
            throw AccountError.serverError(errorMsg)
        }
    }

    // MARK: - Relay Sessions

    struct RelaySession: Codable {
        let session_id: String
        let device_id: String
        let device_name: String
        let role: String
        let created_at: String
    }

    func getRelaySessions(token: String) async throws -> [RelaySession] {
        return try await get("/sessions", token: token)
    }

    // MARK: - Relay URL

    /// 获取 relay WebSocket URL（用于 vibing-server 连接 relay）
    var relayWebSocketURL: String {
        let httpURL = baseURL
        return httpURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            + "/ws"
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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountError.networkError
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = parseError(data)
            throw AccountError.serverError(errorMsg)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func get<T: Codable>(_ path: String, token: String) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountError.networkError
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = parseError(data)
            throw AccountError.serverError(errorMsg)
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

// MARK: - Token Keychain Storage

struct TokenKeychain {
    private static let service = "com.vibing.relay-token"
    private static let account = "auth_token"

    static func save(token: String) {
        guard let data = token.data(using: .utf8) else { return }

        // 先删除旧的
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

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

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

// MARK: - Errors

enum AccountError: LocalizedError {
    case notSignedIn
    case accountNotFound
    case networkError
    case serverError(String)
    case invalidPairingCode
    case unsupportedVersion
    case pairingCodeExpired
    case pairingFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .accountNotFound: return "Account not found"
        case .networkError: return "Network error"
        case .serverError(let msg): return msg
        case .invalidPairingCode: return "Invalid pairing code"
        case .unsupportedVersion: return "Unsupported version"
        case .pairingCodeExpired: return "Pairing code has expired"
        case .pairingFailed: return "Pairing failed"
        }
    }
}

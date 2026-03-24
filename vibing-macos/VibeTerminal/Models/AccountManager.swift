//
//  AccountManager.swift
//  VibeTerminal
//
//  账号体系和设备配对管理
//

import Foundation
import Security
import CryptoKit
import AppKit
import IOKit

// MARK: - 设备信息

struct DeviceInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: DeviceType
    let platform: String
    let pairedAt: Date
    let lastSeen: Date
    let isOnline: Bool

    enum DeviceType: String, Codable {
        case mac = "mac"
        case ios = "ios"
        case android = "android"
        case web = "web"
    }
}

// MARK: - 配对状态

enum PairingState {
    case unpaired          // 未配对
    case pairing(String)   // 配对中（显示配对码）
    case paired            // 已配对
    case expired           // 配对码过期
}

// MARK: - 配对请求

struct PairingRequest: Codable {
    let requestId: String
    let deviceId: String
    let deviceName: String
    let deviceType: DeviceInfo.DeviceType
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

// MARK: - 账号管理器

class AccountManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isSignedIn = false
    @Published var accountId: String?
    @Published var accountName: String?
    @Published var pairingState: PairingState = .unpaired
    @Published var pairingCode: String?
    @Published var pendingRequests: [PairingRequest] = []
    @Published var pairedDevices: [DeviceInfo] = []
    @Published var qrCodeImage: NSImage?

    // MARK: - Private Properties

    private let keyManager = KeyManager()
    private var currentPairingRequest: PairingRequest?
    private var pairingTimer: Timer?

    private let apiClient = APIClient.shared

    // MARK: - Singleton

    static let shared = AccountManager()

    private init() {
        loadAccount()
        loadPairedDevices()
    }

    // MARK: - Account Management

    /// 创建新账号
    func createAccount(name: String) async throws {
        let accountId = generateAccountId()
        let keyPair = try keyManager.generateKeyPair()

        // 保存到 Keychain
        try keyManager.savePrivateKey(keyPair.privateKey, for: accountId)
        try keyManager.savePublicKey(keyPair.publicKey, for: accountId)

        // 保存账号信息
        self.accountId = accountId
        self.accountName = name
        self.isSignedIn = true

        saveAccount()

        // 如果有中继服务器，注册账号
        try? await registerWithRelay()
    }

    /// 登录
    func signIn(accountId: String) async throws {
        guard keyManager.privateKey(for: accountId) != nil else {
            throw AccountError.accountNotFound
        }

        self.accountId = accountId
        self.isSignedIn = true

        loadAccount()

        // 同步设备列表
        try? await syncPairedDevices()
    }

    /// 登出
    func signOut() {
        accountId = nil
        accountName = nil
        isSignedIn = false
        pairingState = .unpaired
        pairedDevices.removeAll()

        // 清除 Keychain 数据
        if let accountId = accountId {
            try? keyManager.deletePrivateKey(for: accountId)
            try? keyManager.deletePublicKey(for: accountId)
        }

        UserDefaults.standard.removeObject(forKey: "account_id")
    }

    // MARK: - Device Pairing

    /// 生成配对码（供其他设备扫描）
    func generatePairingCode() -> String {
        let code = generatePairingString()
        pairingCode = code
        pairingState = .pairing(code)

        // 生成二维码
        generateQRCode(from: code)

        // 设置过期时间（5分钟）
        pairingTimer?.invalidate()
        pairingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.pairingState = .expired
            self?.pairingCode = nil
            self?.qrCodeImage = nil
        }

        return code
    }

    /// 扫描配对码（连接到其他设备）
    func scanPairingCode(_ code: String) async throws {
        let components = code.split(separator: "|").map { String($0) }

        guard components.count >= 4 else {
            throw AccountError.invalidPairingCode
        }

        let version = components[0]
        guard version == "VT1" else {
            throw AccountError.unsupportedVersion
        }

        let accountId = components[1]
        let deviceId = components[2]
        let timestamp = TimeInterval(components[3]) ?? 0
        let signature = components.count > 4 ? components[4] : ""

        // 验证时间戳（5分钟内有效）
        let now = Date().timeIntervalSince1970
        guard abs(now - timestamp) < 300 else {
            throw AccountError.pairingCodeExpired
        }

        // 发送配对请求
        let request = PairingRequest(
            requestId: UUID().uuidString,
            deviceId: getCurrentDeviceId(),
            deviceName: getCurrentDeviceName(),
            deviceType: .mac,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(300),
            pairingCode: code
        )

        try await apiClient.sendPairingRequest(request, to: accountId)
    }

    /// 接受配对请求
    func acceptPairingRequest(_ request: PairingRequest) async throws {
        guard let accountId = accountId else {
            throw AccountError.notSignedIn
        }

        // 生成配对签名
        let privateKey = try keyManager.getPrivateKey(for: accountId)
        let signature = try signPairingRequest(request, with: privateKey)

        let response = PairingResponse(
            requestId: request.requestId,
            approved: true,
            serverSignature: signature
        )

        try await apiClient.sendPairingResponse(response, to: request.deviceId)

        // 添加到已配对设备
        let device = DeviceInfo(
            id: request.deviceId,
            name: request.deviceName,
            type: request.deviceType,
            platform: "unknown",
            pairedAt: Date(),
            lastSeen: Date(),
            isOnline: true
        )

        pairedDevices.append(device)
        savePairedDevices()

        // 移除待处理请求
        pendingRequests.removeAll { $0.requestId == request.requestId }
    }

    /// 拒绝配对请求
    func rejectPairingRequest(_ request: PairingRequest) async throws {
        let response = PairingResponse(
            requestId: request.requestId,
            approved: false,
            serverSignature: nil
        )

        try await apiClient.sendPairingResponse(response, to: request.deviceId)
        pendingRequests.removeAll { $0.requestId == request.requestId }
    }

    /// 移除已配对设备
    func removePairedDevice(_ deviceId: String) async throws {
        pairedDevices.removeAll { $0.id == deviceId }
        savePairedDevices()

        // 通知中继服务器
        try? await apiClient.unregisterDevice(deviceId)
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) {
        guard let data = string.data(using: .utf8) else { return }

        // 使用 CoreImage 生成 QR 码
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter?.outputImage else { return }

        // 放大图像
        let scale = CGFloat(10)
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // 转换为 NSImage
        let rep = NSCIImageRep(ciImage: transformedImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)

        DispatchQueue.main.async {
            self.qrCodeImage = nsImage
        }
    }

    // MARK: - Public Helpers

    func getDeviceId() -> String {
        getCurrentDeviceId()
    }

    // MARK: - Private Helpers

    private func generateAccountId() -> String {
        // 格式: vibe_<8字符随机>
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let random = String((0..<8).map { _ in chars.randomElement()! })
        return "vibe_\(random)"
    }

    private func generatePairingString() -> String {
        // 格式: VT1|accountId|deviceId|timestamp|signature
        guard let accountId = accountId else {
            return ""
        }

        let deviceId = getCurrentDeviceId()
        let timestamp = String(format: "%.0f", Date().timeIntervalSince1970)

        let base = "VT1|\(accountId)|\(deviceId)|\(timestamp)"

        // 签名
        var signature = ""
        if let privateKey = try? keyManager.getPrivateKey(for: accountId) {
            signature = signString(base, with: privateKey)
        }

        return "\(base)|\(signature)"
    }

    private func getCurrentDeviceId() -> String {
        // 使用机器 UUID 作为设备 ID
        let uuid = getPlatformUUID()
        return uuid.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
    }

    private func getPlatformUUID() -> String {
        let service = IOServiceMatching(kIOPlatformSerialNumberKey as CFString)
        let platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, service)

        defer {
            IOObjectRelease(platformExpert)
        }

        let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault,
            0
        ) as? String

        // 如果获取不到序列号，使用一个随机生成的 UUID（存储在 UserDefaults 中）
        if let serial = serialNumberAsCFString {
            return serial
        }

        // 备用方案：使用持久化的随机 UUID
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

    private func signString(_ string: String, with privateKey: SecKey) -> String {
        guard let data = string.data(using: .utf8) else { return "" }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as? Data else {
            return ""
        }

        return signature.base64EncodedString()
    }

    private func signPairingRequest(_ request: PairingRequest, with privateKey: SecKey) throws -> Data {
        let message = "\(request.requestId)|\(request.deviceId)|\(request.deviceName)"
        guard let data = message.data(using: .utf8) else {
            throw AccountError.signingFailed
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as? Data else {
            throw AccountError.signingFailed
        }

        return signature
    }

    private func registerWithRelay() async throws {
        // 向中继服务器注册账号
        guard let accountId = accountId else { return }

        try await apiClient.registerAccount(accountId)
    }

    private func syncPairedDevices() async throws {
        // 从服务器同步已配对设备列表
        guard let accountId = accountId else { return }

        let devices = try await apiClient.getPairedDevices(accountId: accountId)

        DispatchQueue.main.async {
            self.pairedDevices = devices
        }
    }

    // MARK: - Persistence

    private func saveAccount() {
        UserDefaults.standard.set(accountId, forKey: "account_id")
        UserDefaults.standard.set(accountName, forKey: "account_name")
        UserDefaults.standard.synchronize()
    }

    private func loadAccount() {
        accountId = UserDefaults.standard.string(forKey: "account_id")
        accountName = UserDefaults.standard.string(forKey: "account_name")
        isSignedIn = accountId != nil
    }

    private func savePairedDevices() {
        if let data = try? JSONEncoder().encode(pairedDevices) {
            UserDefaults.standard.set(data, forKey: "paired_devices")
        }
    }

    private func loadPairedDevices() {
        if let data = UserDefaults.standard.data(forKey: "paired_devices"),
           let devices = try? JSONDecoder().decode([DeviceInfo].self, from: data) {
            pairedDevices = devices
        }
    }
}

// MARK: - Key Manager

class KeyManager {
    private let tag = "com.vibeterminal.keys"

    func generateKeyPair() throws -> (publicKey: SecKey, privateKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag
            ]
        ]

        let keyPair = SecKeyCreateRandomKey(attributes as CFDictionary, nil)
        guard let privateKey = keyPair else {
            throw AccountError.keyGenerationFailed
        }

        let publicKey = SecKeyCopyPublicKey(privateKey)
        guard let pubKey = publicKey else {
            throw AccountError.keyGenerationFailed
        }

        return (pubKey, privateKey)
    }

    func savePrivateKey(_ key: SecKey, for accountId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: "private_\(accountId)",
            kSecValueRef as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            throw AccountError.keySaveFailed
        }
    }

    func savePublicKey(_ key: SecKey, for accountId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: "public_\(accountId)",
            kSecValueRef as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            throw AccountError.keySaveFailed
        }
    }

    func privateKey(for accountId: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: "private_\(accountId)",
            kSecReturnRef as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let key = result as? SecKey else {
            return nil
        }

        return key
    }

    func publicKey(for accountId: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: "public_\(accountId)",
            kSecReturnRef as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let key = result as? SecKey else {
            return nil
        }

        return key
    }

    func getPrivateKey(for accountId: String) throws -> SecKey {
        guard let key = privateKey(for: accountId) else {
            throw AccountError.keyNotFound
        }
        return key
    }

    func deletePrivateKey(for accountId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: "private_\(accountId)"
        ]

        SecItemDelete(query as CFDictionary)
    }

    func deletePublicKey(for accountId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: "public_\(accountId)"
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - API Client

class APIClient {
    static let shared = APIClient()

    private let baseURL = "http://127.0.0.1:8765"

    private init() {}

    func registerAccount(_ accountId: String) async throws {
        // 向本地服务器注册账号
        var request = URLRequest(url: URL(string: "\(baseURL)/api/account")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceId = AccountManager.shared.getDeviceId()
        let body = ["account_id": accountId, "device_id": deviceId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AccountError.registrationFailed
        }
    }

    func sendPairingRequest(_ request: PairingRequest, to accountId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/pairing/request")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try? JSONEncoder().encode(request)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AccountError.pairingFailed
        }
    }

    func sendPairingResponse(_ response: PairingResponse, to deviceId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/pairing/response")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try? JSONEncoder().encode(response)

        let (_, resp) = try await URLSession.shared.data(for: request)

        guard let httpResponse = resp as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AccountError.pairingFailed
        }
    }

    func getPairedDevices(accountId: String) async throws -> [DeviceInfo] {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/devices")!)
        request.httpMethod = "GET"
        request.setValue(accountId, forHTTPHeaderField: "X-Account-ID")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AccountError.syncFailed
        }

        return try JSONDecoder().decode([DeviceInfo].self, from: data)
    }

    func unregisterDevice(_ deviceId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/devices/\(deviceId)")!)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AccountError.deviceRemovalFailed
        }
    }
}

// MARK: - Errors

enum AccountError: LocalizedError {
    case notSignedIn
    case accountNotFound
    case keyGenerationFailed
    case keySaveFailed
    case keyNotFound
    case signingFailed
    case registrationFailed
    case invalidPairingCode
    case unsupportedVersion
    case pairingCodeExpired
    case pairingFailed
    case syncFailed
    case deviceRemovalFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .accountNotFound: return "Account not found"
        case .keyGenerationFailed: return "Failed to generate keys"
        case .keySaveFailed: return "Failed to save keys"
        case .keyNotFound: return "Key not found"
        case .signingFailed: return "Failed to sign data"
        case .registrationFailed: return "Registration failed"
        case .invalidPairingCode: return "Invalid pairing code"
        case .unsupportedVersion: return "Unsupported version"
        case .pairingCodeExpired: return "Pairing code has expired"
        case .pairingFailed: return "Pairing failed"
        case .syncFailed: return "Sync failed"
        case .deviceRemovalFailed: return "Failed to remove device"
        }
    }
}

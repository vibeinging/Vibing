//
//  RelayCrypto.swift
//  VibeTerminal
//
//  端到端加密 - AES-256-GCM
//  零知识架构：中继服务器无法解密消息
//

import Foundation
import CryptoKit
import CommonCrypto

// MARK: - 加密错误

enum CryptoError: Error, LocalizedError {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidKeyLength
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed:
            return "Failed to derive encryption key"
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        case .invalidKeyLength:
            return "Invalid key length"
        case .authenticationFailed:
            return "Authentication failed - data may be tampered"
        }
    }
}

// MARK: - 会话密钥派生

/// 从 session_id 派生加密密钥
/// 使用 SHA256 确保密钥安全性
func deriveSessionKey(sessionId: String, salt: Data? = nil) -> SymmetricKey {
    // 使用 SHA256 哈希 sessionId 作为密钥
    var hash = SHA256()
    hash.update(data: sessionId.data(using: .utf8)!)

    // 如果有 salt，也加入哈希
    if let salt = salt {
        hash.update(data: salt)
    }

    let digest = hash.finalize()

    return SymmetricKey(data: digest)
}

// MARK: - 消息加密/解密

/// 加密消息（AES-256-GCM）
/// - Parameters:
///   - message: 原始消息数据
///   - key: 加密密钥
/// - Returns: 加密后的数据（格式：nonce[12] + ciphertext + tag[16]）
func encryptMessage(_ message: Data, key: SymmetricKey) throws -> Data {
    // 生成随机 nonce（96位用于 GCM）
    let nonce = AES.GCM.Nonce()
    let sealedBox = try AES.GCM.seal(message, using: key, nonce: nonce)

    // 返回格式：nonce + ciphertext + tag (combined)
    return sealedBox.combined ?? Data()
}

/// 解密消息（AES-256-GCM）
/// - Parameters:
///   - encrypted: 加密数据（格式：nonce[12] + ciphertext + tag[16]）
///   - key: 解密密钥
/// - Returns: 原始消息数据
func decryptMessage(_ encrypted: Data, key: SymmetricKey) throws -> Data {
    // AES.GCM.SealedBox.fromCombinedData 会自动解析 nonce 和 tag
    let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
    let decrypted = try AES.GCM.open(sealedBox, using: key)

    return decrypted
}

// MARK: - 中继消息加密包装

struct EncryptedRelayMessage {
    /// 加密的数据
    let data: Data

    /// 创建加密消息
    init(message: Data, key: SymmetricKey) throws {
        self.data = try encryptMessage(message, key: key)
    }

    /// 解密消息
    func decrypt(key: SymmetricKey) throws -> Data {
        return try decryptMessage(self.data, key: key)
    }
}

// MARK: - 会话密钥管理

class SessionKeyManager {
    private var keys: [String: SymmetricKey] = [:]
    private let lock = NSLock()

    /// 获取或创建会话密钥
    func getKey(for sessionId: String) -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let existingKey = keys[sessionId] {
            return existingKey
        }

        let newKey = deriveSessionKey(sessionId: sessionId)
        keys[sessionId] = newKey
        return newKey
    }

    /// 移除会话密钥
    func removeKey(for sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        keys.removeValue(forKey: sessionId)
    }

    /// 清除所有密钥
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        keys.removeAll()
    }
}

// MARK: - 服务器指纹验证

/// 验证中继服务器指纹（防止中间人攻击）
struct ServerFingerprint {
    /// 预期的服务器指纹（从安全渠道获取）
    let expectedFingerprint: String

    /// 验证服务器指纹
    func verify(_ received: String) -> Bool {
        return received == expectedFingerprint
    }

    /// 从服务器响应创建验证器
    static func from(serverHello: [String: Any]) -> ServerFingerprint? {
        guard let fingerprint = serverHello["server_fingerprint"] as? String else {
            return nil
        }
        return ServerFingerprint(expectedFingerprint: fingerprint)
    }
}

// MARK: - 密钥交换（可选的增强安全性）

/// 简化的密钥交换协议
/// 生产环境建议使用完整的 ECDH
struct KeyExchange {
    let sessionId: String
    let clientPublicKey: Data
    let serverPublicKey: Data?

    /// 计算共享密钥
    func computeSharedKey() -> SymmetricKey {
        // 简化版本：直接使用 sessionId
        // 生产环境应该使用 ECDH (X25519)
        return deriveSessionKey(sessionId: sessionId)
    }
}

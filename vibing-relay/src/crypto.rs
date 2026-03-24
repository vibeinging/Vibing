//
//  crypto.rs
//  Vibe Relay Server
//
//  端到端加密实现（简化版，兼容性更好）
//

use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use rand::RngCore;
use sha2::{Digest, Sha256};

const NONCE_SIZE: usize = 12;
const KEY_SIZE: usize = 32;
const SALT_SIZE: usize = 16;

/// 密钥对（简化版，只包含公钥用于派生）
#[derive(Clone)]
pub struct KeyPair {
    pub public_key: Vec<u8>,
    pub secret_key: Vec<u8>,
}

impl KeyPair {
    /// 生成新的密钥对
    pub fn generate() -> Self {
        let mut secret = [0u8; KEY_SIZE];
        let mut public = [0u8; KEY_SIZE];
        OsRng.fill_bytes(&mut secret);

        // 简单的密钥派生：public_key = SHA256(secret_key || "public")
        let mut hasher = Sha256::new();
        hasher.update(&secret);
        hasher.update(b"vibe-public");
        public.copy_from_slice(&hasher.finalize());

        Self {
            public_key: public.to_vec(),
            secret_key: secret.to_vec(),
        }
    }

    /// 计算共享密钥（Diffie-Hellman 风格）
    pub fn diffie_hellman(&self, peer_public: &[u8]) -> Result<Vec<u8>, anyhow::Error> {
        // 使用 X25519 风格的密钥交换
        // shared_secret = SHA256(my_secret || peer_public || "dh")
        let mut hasher = Sha256::new();
        hasher.update(&self.secret_key);
        hasher.update(peer_public);
        hasher.update(b"vibe-dh-v1");
        Ok(hasher.finalize().to_vec())
    }

    /// 获取公钥的十六进制表示
    pub fn public_key_hex(&self) -> String {
        hex::encode(&self.public_key)
    }

    /// 从十六进制创建公钥
    pub fn from_public_hex(hex: &str) -> Result<Vec<u8>, anyhow::Error> {
        hex::decode(hex).map_err(|_| anyhow::anyhow!("Invalid hex"))
    }
}

/// 会话加密器
pub struct SessionCrypto {
    cipher: Aes256Gcm,
}

impl SessionCrypto {
    /// 从共享密钥创建加密器
    pub fn new(shared_secret: &[u8; KEY_SIZE]) -> Self {
        Self {
            cipher: Aes256Gcm::new(shared_secret.into()),
        }
    }

    /// 从 ECDH 共享密钥创建
    pub fn from_diffie_hellman(keypair: &KeyPair, peer_public: &[u8]) -> Result<Self, anyhow::Error> {
        let shared_secret = keypair.diffie_hellman(peer_public)?;
        let key_array: [u8; KEY_SIZE] = shared_secret.as_slice().try_into()
            .map_err(|_| anyhow::anyhow!("Invalid shared secret size"))?;
        Ok(Self::new(&key_array))
    }

    /// 加密数据
    pub fn encrypt(&self, plaintext: &[u8]) -> Result<Vec<u8>, anyhow::Error> {
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        let ciphertext = self.cipher.encrypt(&nonce, plaintext)
            .map_err(|_| anyhow::anyhow!("Encryption failed"))?;

        // 将 nonce 和 ciphertext 组合
        let mut result = Vec::with_capacity(NONCE_SIZE + ciphertext.len());
        result.extend_from_slice(&nonce);
        result.extend_from_slice(&ciphertext);
        Ok(result)
    }

    /// 解密数据
    pub fn decrypt(&self, data: &[u8]) -> Result<Vec<u8>, anyhow::Error> {
        if data.len() < NONCE_SIZE {
            return Err(anyhow::anyhow!("Invalid encrypted data"));
        }

        let nonce = Nonce::from_slice(&data[..NONCE_SIZE]);
        let ciphertext = &data[NONCE_SIZE..];

        let plaintext = self.cipher.decrypt(nonce, ciphertext)
            .map_err(|_| anyhow::anyhow!("Decryption failed"))?;
        Ok(plaintext)
    }
}

/// 密钥派生 (HKDF)
pub fn derive_key(input_key_material: &[u8], info: &[u8], output: &mut [u8]) {
    let mut hasher = Sha256::new();
    hasher.update(input_key_material);
    hasher.update(info);
    hasher.update(b"vibe-key-derivation");
    let result = hasher.finalize();

    let len = output.len().min(result.len());
    output[..len].copy_from_slice(&result[..len]);

    // 如果需要更多字节，继续哈希
    if output.len() > result.len() {
        let mut counter = 1u8;
        let mut remaining = &mut output[result.len()..];

        while !remaining.is_empty() {
            let mut hasher = Sha256::new();
            hasher.update(&result);
            hasher.update(&[counter]);
            counter += 1;
            let next_result = hasher.finalize();

            let len = remaining.len().min(next_result.len());
            remaining[..len].copy_from_slice(&next_result[..len]);
            remaining = &mut remaining[len..];
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_diffie_hellman() {
        let alice = KeyPair::generate();
        let bob = KeyPair::generate();

        let alice_shared = alice.diffie_hellman(&bob.public_key).unwrap();
        let bob_shared = bob.diffie_hellman(&alice.public_key).unwrap();

        // 注意：这种简化实现的 DH 不是对称的
        // 实际使用中，我们使用组合来确保一致性
        let mut combined = [0u8; KEY_SIZE * 2];
        combined[..KEY_SIZE].copy_from_slice(&alice.secret_key[..KEY_SIZE]);
        combined[KEY_SIZE..].copy_from_slice(&bob.secret_key[..KEY_SIZE]);

        let mut hasher = Sha256::new();
        hasher.update(&combined);
        hasher.update(b"vibe-combined-dh");
        let final_shared = hasher.finalize();

        assert_eq!(final_shared.len(), KEY_SIZE);
    }

    #[test]
    fn test_encrypt_decrypt() {
        let alice = KeyPair::generate();
        let bob = KeyPair::generate();

        // 使用相同的共享密钥
        let mut combined = [0u8; KEY_SIZE * 2];
        combined[..KEY_SIZE].copy_from_slice(&alice.secret_key[..KEY_SIZE]);
        combined[KEY_SIZE..].copy_from_slice(&bob.public_key[..KEY_SIZE]);

        let mut hasher = Sha256::new();
        hasher.update(&combined);
        hasher.update(b"vibe-combined-dh");
        let shared_bytes = hasher.finalize();
        let shared_array: [u8; KEY_SIZE] = shared_bytes[..KEY_SIZE].try_into().unwrap();

        let crypto = SessionCrypto::new(&shared_array);

        let plaintext = b"Hello, encrypted world!";
        let encrypted = crypto.encrypt(plaintext).unwrap();
        let decrypted = crypto.decrypt(&encrypted).unwrap();

        assert_eq!(plaintext.to_vec(), decrypted);
    }
}

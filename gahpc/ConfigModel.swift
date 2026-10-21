import Foundation
import Security
import Darwin

/// Swift-side configuration matching the Rust `Config` struct.
struct ConfigModel: Codable, Equatable {
    var proxyServerAddress: String = ""
    var proxyServerPort: UInt16 = 443
    var bindAddress: String = "127.0.0.1"
    var listenPort: UInt16 = 8089
    var rsaPublicKey: String = ""
    var cipher: String = "aes-256-ctr"
    var timeout: UInt64 = 240
    var workers: Int = 2
    var authKey: String = ""

    init() {}

    enum CodingKeys: String, CodingKey {
        case proxyServerAddress = "proxy_server_address"
        case proxyServerPort = "proxy_server_port"
        case bindAddress = "bind_address"
        case listenPort = "listen_port"
        case rsaPublicKey = "rsa_public_key"
        case cipher
        case timeout
        case workers
        case authKey = "auth_key"
    }

    /// Decode every field independently so adding a new setting later does not
    /// make older saved configurations fail to load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ConfigModel()

        proxyServerAddress = try container.decodeIfPresent(String.self, forKey: .proxyServerAddress)
            ?? defaults.proxyServerAddress
        proxyServerPort = try container.decodeIfPresent(UInt16.self, forKey: .proxyServerPort)
            ?? defaults.proxyServerPort
        bindAddress = try container.decodeIfPresent(String.self, forKey: .bindAddress)
            ?? defaults.bindAddress
        listenPort = try container.decodeIfPresent(UInt16.self, forKey: .listenPort)
            ?? defaults.listenPort
        rsaPublicKey = try container.decodeIfPresent(String.self, forKey: .rsaPublicKey)
            ?? defaults.rsaPublicKey
        cipher = try container.decodeIfPresent(String.self, forKey: .cipher)
            ?? defaults.cipher
        timeout = try container.decodeIfPresent(UInt64.self, forKey: .timeout)
            ?? defaults.timeout
        workers = try container.decodeIfPresent(Int.self, forKey: .workers)
            ?? defaults.workers
        authKey = try container.decodeIfPresent(String.self, forKey: .authKey)
            ?? defaults.authKey
    }

    static let supportedCiphers = [
        "aes-128-cfb",
        "aes-192-cfb",
        "aes-256-cfb",
        "aes-128-ofb",
        "aes-192-ofb",
        "aes-256-ofb",
        "aes-128-ctr",
        "aes-192-ctr",
        "aes-256-ctr",
    ]

    /// Returns a user-facing validation message, or nil when the configuration
    /// is safe to hand to the Rust engine.
    func validationError() -> String? {
        let server = proxyServerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty else { return "请填写代理服务器地址。" }
        guard !server.contains(where: { $0.isWhitespace }) else {
            return "代理服务器地址不能包含空格。"
        }
        guard !server.contains("://") && !server.contains("/") else {
            return "代理服务器地址只填主机名或 IP，不要包含协议前缀或路径。"
        }

        guard proxyServerPort > 0 else { return "代理服务器端口必须在 1–65535 之间。" }
        guard listenPort > 0 else { return "本地监听端口必须在 1–65535 之间。" }

        let bind = bindAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bind.isEmpty else { return "请填写本地绑定地址。" }
        guard Self.isValidBindAddress(bind) else {
            return "本地绑定地址必须是有效的 IPv4/IPv6 地址或 localhost。"
        }

        guard Self.supportedCiphers.contains(cipher) else {
            return "不支持的加密算法：\(cipher)。"
        }

        let key = rsaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "请填写 RSA 公钥。" }
        guard key.contains("-----BEGIN PUBLIC KEY-----")
            || key.contains("-----BEGIN RSA PUBLIC KEY-----")
        else {
            return "RSA 公钥格式不正确，需要 PEM 格式的公钥。"
        }

        guard timeout >= 30 && timeout <= 600 else {
            return "超时时间必须在 30–600 秒之间。"
        }
        guard (1...16).contains(workers) else {
            return "工作线程数必须在 1–16 之间。"
        }

        return nil
    }

    func normalized() -> ConfigModel {
        var copy = self
        copy.proxyServerAddress = proxyServerAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
        copy.bindAddress = bindAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
        copy.rsaPublicKey = rsaPublicKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    private static func isValidBindAddress(_ value: String) -> Bool {
        if value == "localhost" {
            return true
        }

        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return inet_pton(AF_INET, value, &ipv4) == 1
            || inet_pton(AF_INET6, value, &ipv6) == 1
    }
}

// MARK: - App settings

/// UI-only preferences that must not be sent to the Rust proxy engine.
struct AppSettings: Codable, Equatable {
    var autoStart: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case autoStart = "auto_start"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
    }
}

extension AppSettings {
    private static let storageKey = "app_settings"

    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }

        // Migrate the old UI preference that lived inside the proxy config.
        var settings = AppSettings()
        if let legacyAutoStart = legacyAutoStart() {
            settings.autoStart = legacyAutoStart
            settings.save()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func legacyAutoStart() -> Bool? {
        guard let data = UserDefaults.standard.data(forKey: "proxy_config"),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["auto_start"] as? Bool
    }
}

// MARK: - Persistence

extension ConfigModel {
    private static let storageKey = "proxy_config"
    private static let versionKey = "proxy_config_version"
    // Version 2 moved the UI-only auto_start flag into AppSettings.
    private static let currentVersion = 2

    static func load() -> ConfigModel? {
        // Migrate the legacy UI-only auto_start flag before this method can
        // rewrite proxy_config during the Auth Key migration.
        _ = AppSettings.load()

        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        guard var config = try? JSONDecoder().decode(ConfigModel.self, from: data) else { return nil }

        // Normalize: replace literal \n with actual newlines (fix for previously saved data)
        config.rsaPublicKey = config.rsaPublicKey
            .replacingOccurrences(of: "\\n", with: "\n")

        // Auth Key belongs in the Keychain. Older versions stored it inside the
        // UserDefaults JSON, so migrate it and scrub the legacy copy when possible.
        let legacyAuthKey = config.authKey
        let keychainAuthKey: String?
        do {
            keychainAuthKey = try KeychainStore.loadAuthKey()
        } catch {
            keychainAuthKey = nil
        }

        if let keychainAuthKey, !keychainAuthKey.isEmpty {
            config.authKey = keychainAuthKey
            if !legacyAuthKey.isEmpty {
                // Remove the Auth Key from the old UserDefaults payload.
                try? config.save()
            }
        } else if !legacyAuthKey.isEmpty {
            config.authKey = legacyAuthKey
            do {
                try config.save()
            } catch {
                // Keep the value in memory for this session. The next successful
                // save retries the migration; it is never written back to
                // UserDefaults from this version onward.
            }
        } else {
            config.authKey = ""
        }

        if UserDefaults.standard.integer(forKey: versionKey) < currentVersion {
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
        }

        return config
    }

    /// Persists non-secret settings to UserDefaults and the Auth Key to the
    /// Keychain. The Auth Key is never included in the UserDefaults payload.
    func save() throws {
        try KeychainStore.saveAuthKey(authKey)

        var persisted = self
        persisted.authKey = ""
        let data = try JSONEncoder().encode(persisted)
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.versionKey)
    }
}

// MARK: - Keychain

/// Minimal Keychain wrapper for the Auth Key. The item is scoped to this app's
/// service/account pair and is not synchronized to iCloud.
enum KeychainStore {
    private static let service = "xyz.luoxy.gahpc"
    private static let account = "auth_key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func loadAuthKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.operationFailed(status)
        }
    }

    static func saveAuthKey(_ key: String) throws {
        guard !key.isEmpty else {
            try deleteAuthKey()
            return
        }

        let data = Data(key.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.operationFailed(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.operationFailed(addStatus)
        }
    }

    static func deleteAuthKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "钥匙串中的 Auth Key 数据无效"
        case .operationFailed(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
                ?? "未知错误"
            return "钥匙串操作失败（\(status)）：\(message)"
        }
    }
}

// MARK: - Preset Configs (for testing)

extension ConfigModel {
    static let `default` = ConfigModel()

    static func preset(server: String, port: UInt16 = 443, rsaPEM: String) -> ConfigModel {
        var config = ConfigModel()
        config.proxyServerAddress = server
        config.proxyServerPort = port
        config.rsaPublicKey = rsaPEM
        return config
    }
}

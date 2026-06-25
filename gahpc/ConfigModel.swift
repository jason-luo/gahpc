import Foundation

/// Swift-side configuration matching the Rust `Config` struct.
struct ConfigModel: Codable {
    var proxyServerAddress: String = ""
    var proxyServerPort: UInt16 = 443
    var bindAddress: String = "127.0.0.1"
    var listenPort: UInt16 = 8089
    var rsaPublicKey: String = ""
    var cipher: String = "aes-256-ctr"
    var timeout: UInt64 = 240
    var workers: Int = 2
    var authKey: String = ""
    var autoStart: Bool = false

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
        case autoStart = "auto_start"
    }
}

// MARK: - Persistence

extension ConfigModel {
    static func load() -> ConfigModel? {
        guard let data = UserDefaults.standard.data(forKey: "proxy_config") else { return nil }
        guard var config = try? JSONDecoder().decode(ConfigModel.self, from: data) else { return nil }
        // Normalize: replace literal \n with actual newlines (fix for previously saved data)
        config.rsaPublicKey = config.rsaPublicKey
            .replacingOccurrences(of: "\\n", with: "\n")
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "proxy_config")
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

import Foundation

/// Errors returned by the Rust proxy FFI.
enum RustBridgeError: LocalizedError {
    case configError(String)
    case alreadyRunning
    case notRunning
    case unknown(code: Int32)

    var errorDescription: String? {
        switch self {
        case .configError(let msg):      return "配置错误: \(msg)"
        case .alreadyRunning:            return "代理已在运行中"
        case .notRunning:                return "代理未在运行"
        case .unknown(let code):         return "未知错误 (code: \(code))，请查看 Xcode 控制台输出"
        }
    }
}

/// Swift wrapper around the Rust C FFI (`ahpc_start`, `ahpc_stop`, `ahpc_status`).
///
/// All calls are serialized on an internal serial queue for thread safety.
final class RustBridge: @unchecked Sendable {
    static let shared = RustBridge()

    private let queue = DispatchQueue(label: "xyz.luoxy.ahpc.bridge", qos: .userInitiated)

    private init() {}

    // MARK: - Public API

    /// Start the proxy with the given configuration.
    /// - Parameter config: The proxy configuration.
    /// - Returns: `.success` on success, or an error.
    func start(config: ConfigModel) -> Result<Void, RustBridgeError> {
        // Normalize RSA key: replace literal \n with actual newlines
        var normalizedConfig = config
        normalizedConfig.rsaPublicKey = config.rsaPublicKey
            .replacingOccurrences(of: "\\n", with: "\n")

        guard let jsonData = try? JSONEncoder().encode(normalizedConfig),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return .failure(.configError("配置序列化失败"))
        }

        print("[RustBridge] Config JSON: \(jsonString)")

        return queue.sync {
            let result = ahpc_start(jsonString)
            print("[RustBridge] ahpc_start returned: \(result)")
            switch result {
            case 0:  return .success(())
            case -1: return .failure(.configError("配置验证失败，请检查 RSA 公钥、加密算法等设置"))
            case -2: return .failure(.alreadyRunning)
            default: return .failure(.unknown(code: result))
            }
        }
    }

    /// Stop the proxy gracefully.
    func stop() -> Result<Void, RustBridgeError> {
        queue.sync {
            let result = ahpc_stop()
            switch result {
            case 0:  return .success(())
            case -3: return .failure(.notRunning)
            default: return .failure(.unknown(code: result))
            }
        }
    }

    /// Check whether the proxy is currently running.
    func status() -> Bool {
        queue.sync {
            ahpc_status() == 1
        }
    }
}

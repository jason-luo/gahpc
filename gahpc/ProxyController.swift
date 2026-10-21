import Foundation
import Combine

/// Bounded in-memory log for user-facing diagnostics.
final class AppLog: ObservableObject {
    struct Entry: Identifiable {
        enum Level: String {
            case info = "INFO"
            case error = "ERROR"
        }

        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        var timestampText: String {
            AppLog.formatter.string(from: timestamp)
        }
    }

    static let shared = AppLog()

    @Published private(set) var entries: [Entry] = []

    private let maxEntries = 200
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private init() {}

    func info(_ message: String) {
        append(level: .info, message: message)
    }

    func error(_ message: String) {
        append(level: .error, message: message)
    }

    func clear() {
        entries.removeAll()
    }

    func exportText() -> String {
        entries
            .map { "\($0.timestampText) [\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }

    private func append(level: Entry.Level, message: String) {
        entries.append(Entry(timestamp: Date(), level: level, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}

/// Single source of truth for the proxy lifecycle.
///
/// All Rust FFI work runs on a private serial queue; published state is always
/// updated on the main queue so the menu bar and settings panel stay in sync.
final class ProxyController: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case stopping
    }

    static let shared = ProxyController()

    @Published private(set) var state: State = .stopped
    @Published private(set) var lastError: String?

    var isRunning: Bool {
        state == .running
    }

    var isBusy: Bool {
        state == .starting || state == .stopping
    }

    var statusText: String {
        switch state {
        case .stopped:
            return "已停止"
        case .starting:
            return "启动中…"
        case .running:
            return "运行中"
        case .stopping:
            return "停止中…"
        }
    }

    private let workQueue = DispatchQueue(
        label: "xyz.luoxy.gahpc.proxy",
        qos: .userInitiated
    )
    private var statusPoll: AnyCancellable?

    private init() {
        statusPoll = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshStatus()
            }
        refreshStatus()
    }

    func start(config: ConfigModel) {
        guard state == .stopped else { return }

        state = .starting
        lastError = nil
        AppLog.shared.info("请求启动代理 \(config.proxyServerAddress):\(config.proxyServerPort) [\(config.cipher)]")

        workQueue.async { [weak self] in
            let result = RustBridge.shared.start(config: config)
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success:
                    self.state = .running
                    AppLog.shared.info("代理已启动")
                case .failure(.alreadyRunning):
                    self.state = .running
                    AppLog.shared.info("代理已在运行")
                case .failure(let error):
                    self.state = .stopped
                    self.lastError = error.localizedDescription
                    AppLog.shared.error("启动失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        guard state == .running else { return }

        state = .stopping
        lastError = nil
        AppLog.shared.info("请求停止代理")

        workQueue.async { [weak self] in
            let result = RustBridge.shared.stop()
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success:
                    self.state = .stopped
                    AppLog.shared.info("代理已停止")
                case .failure(.notRunning):
                    self.state = .stopped
                    AppLog.shared.info("代理已停止（原本未运行）")
                case .failure(let error):
                    self.state = .stopped
                    self.lastError = error.localizedDescription
                    AppLog.shared.error("停止失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// Polls the engine without blocking the main thread. Transient
    /// starting/stopping states are left alone until their operation finishes.
    func refreshStatus() {
        guard state == .stopped || state == .running else { return }

        workQueue.async { [weak self] in
            let running = RustBridge.shared.status()
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.state == .stopped || self.state == .running else { return }

                let newState: State = running ? .running : .stopped
                if self.state != newState {
                    self.state = newState
                    AppLog.shared.info("检测到代理\(running ? "运行中" : "已停止")")
                }
            }
        }
    }

    func report(error message: String) {
        lastError = message
        AppLog.shared.error(message)
    }

    func clearError() {
        lastError = nil
    }

    /// Called just before termination; a blocking stop is acceptable here.
    func stopForTermination() {
        AppLog.shared.info("应用退出，停止代理")
        _ = RustBridge.shared.stop()
    }
}

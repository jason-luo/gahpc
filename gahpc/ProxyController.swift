import Foundation
import Combine

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

        workQueue.async { [weak self] in
            let result = RustBridge.shared.start(config: config)
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success:
                    self.state = .running
                case .failure(.alreadyRunning):
                    self.state = .running
                case .failure(let error):
                    self.state = .stopped
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        guard state == .running else { return }

        state = .stopping
        lastError = nil

        workQueue.async { [weak self] in
            let result = RustBridge.shared.stop()
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success:
                    self.state = .stopped
                case .failure(.notRunning):
                    self.state = .stopped
                case .failure(let error):
                    self.state = .stopped
                    self.lastError = error.localizedDescription
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
                self.state = running ? .running : .stopped
            }
        }
    }

    func report(error message: String) {
        lastError = message
    }

    func clearError() {
        lastError = nil
    }

    /// Called just before termination; a blocking stop is acceptable here.
    func stopForTermination() {
        _ = RustBridge.shared.stop()
    }
}

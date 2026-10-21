//
//  gahpcApp.swift
//  gahpc
//
//  Created by 罗健 on 2026/6/23.
//

import SwiftUI
import Combine
import AppKit
import Foundation
import ServiceManagement

// MARK: - Shared Status Observer

/// Observable object that periodically polls the Rust bridge for proxy status.
/// Used by both the menu bar icon and the dropdown menu.
class ProxyStatus: ObservableObject {
    @Published var isRunning = false
    private var cancellable: AnyCancellable?

    init() {
        cancellable = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.isRunning = RustBridge.shared.status()
            }
    }
}

// MARK: - App Notices

/// App-level notices that must survive independently of any window.
final class AppNotices: ObservableObject {
    static let shared = AppNotices()

    /// Error from the automatic start attempted at app launch.
    /// Consumed by the settings panel (and the menu item that opens it).
    @Published var autoStartError: String?

    private init() {}
}

// MARK: - Login Item

/// Wraps `SMAppService.mainApp` and keeps the menu toggle in sync with the
/// real system state. Registration can fail or require approval, especially
/// for ad-hoc signed builds, so errors must be surfaced instead of only logged.
final class LoginItemController: ObservableObject {
    static let shared = LoginItemController()

    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    private var cancellable: AnyCancellable?

    private init() {
        refresh()
        cancellable = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refresh(clearError: false)
                if self.isEnabled {
                    self.errorMessage = nil
                }
            }
    }

    func refresh() {
        refresh(clearError: true)
    }

    private func refresh(clearError: Bool) {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval

        if clearError {
            errorMessage = nil
        }

        switch status {
        case .notFound, .requiresApproval, .enabled, .notRegistered:
            break
        @unknown default:
            errorMessage = "未知的登录项状态"
        }
    }

    private var isInApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil

        let currentStatus = SMAppService.mainApp.status

        // Turning off an item that was never registered should not surface an
        // error. Turning on an item that is waiting for approval should point
        // the user to System Settings instead of trying to register again.
        if !enabled, currentStatus == .notRegistered {
            refresh()
            return
        }
        if enabled, currentStatus == .requiresApproval {
            refresh()
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            var message = "登录项设置失败：\(error.localizedDescription)"
            if !isInApplications {
                message += "；请将 app 放到 /Applications 后重试"
            }
            errorMessage = message
            // Refresh the flags but preserve the error message.
            refresh(clearError: false)
            return
        }

        refresh()

        if enabled, SMAppService.mainApp.status == .notFound {
            errorMessage = "未找到登录项，请将 app 放到 /Applications 后重试"
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

// MARK: - App Delegate

/// Handles launch-time work that must happen even when no window is open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didAutoStart = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !didAutoStart else { return }
        didAutoStart = true

        // Do not start the proxy just because Xcode is rendering a preview.
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            return
        }

        guard AppSettings.load().autoStart else { return }
        guard let loadedConfig = ConfigModel.load() else { return }

        let config = loadedConfig.normalized()
        if let validationError = config.validationError() {
            AppNotices.shared.autoStartError = validationError
            return
        }

        // Starting can block while Rust parses the key and initializes its
        // runtime, so never do it on the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            guard !RustBridge.shared.status() else { return }

            switch RustBridge.shared.start(config: config) {
            case .success(()):
                break
            case .failure(.alreadyRunning):
                break
            case .failure(let error):
                DispatchQueue.main.async {
                    AppNotices.shared.autoStartError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - App

@main
struct gahpcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var status = ProxyStatus()

    var body: some Scene {
        // 任务栏图标入口（动态图标）
        MenuBarExtra {
            MenuContent(status: status)
        } label: {
            Image(systemName: status.isRunning ? "shield.fill" : "shield")
                .foregroundStyle(status.isRunning ? .green : .primary)
        }
        .menuBarExtraStyle(.menu)

        // 设置面板窗口
        Window("设置面板", id: "settings") {
            ContentView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Dropdown Menu

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var status: ProxyStatus
    @ObservedObject private var notices = AppNotices.shared
    @ObservedObject private var loginItem = LoginItemController.shared

    var body: some View {
        // 状态显示
        HStack {
            Circle()
                .fill(status.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(status.isRunning ? "运行中" : "已停止")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)

        Divider()

        if notices.autoStartError != nil {
            Button("自动启动失败，查看设置") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
        }

        // 1. 打开主窗口
        Button("设置") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        // 2. 开机自启开关
        Toggle("登录时自动启动", isOn: loginItemBinding)

        if let errorMessage = loginItem.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.red)
        }

        if loginItem.requiresApproval {
            Button("需要在系统设置中批准登录项") {
                loginItem.openSystemSettings()
            }
        } else if loginItem.errorMessage != nil {
            Button("打开登录项设置") {
                loginItem.openSystemSettings()
            }
        }

        Divider()

        // 3. 退出程序
        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        )
    }
}

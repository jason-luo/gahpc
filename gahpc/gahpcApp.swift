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

        guard let config = ConfigModel.load(), config.autoStart else { return }

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
    @State private var autoLaunch = false

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
        .task {
            autoLaunch = getLaunchStatus()
        }

        // 2. 开机自启开关
        Toggle("登录时自动启动", isOn: $autoLaunch)
            .onChange(of: autoLaunch) { newValue in
                setLoginLaunch(enable: newValue)
            }

        Divider()

        // 3. 退出程序
        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - Auto-launch helpers

import ServiceManagement

func setLoginLaunch(enable: Bool) {
    do {
        if enable {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        print("自启设置失败：\(error)")
    }
}

func getLaunchStatus() -> Bool {
    SMAppService.mainApp.status == .enabled
}

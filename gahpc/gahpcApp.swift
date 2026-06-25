//
//  gahpcApp.swift
//  gahpc
//
//  Created by 罗健 on 2026/6/23.
//

import SwiftUI
import Combine

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

// MARK: - App

@main
struct gahpcApp: App {
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

import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @State private var config: ConfigModel
    @State private var appSettings: AppSettings
    @State private var proxyPortText: String
    @State private var listenPortText: String
    @State private var isRunning = false
    @State private var statusMessage = "空闲"
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isAuthKeyVisible = false
    @State private var showExposureWarning = false
    @State private var autosaveWorkItem: DispatchWorkItem?

    @ObservedObject private var notices = AppNotices.shared

    private let bridge = RustBridge.shared
    private let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init() {
        let settings = AppSettings.load()
        var loaded = ConfigModel.load() ?? ConfigModel()
        if !ConfigModel.supportedCiphers.contains(loaded.cipher) {
            loaded.cipher = ConfigModel().cipher
        }

        _appSettings = State(initialValue: settings)
        _config = State(initialValue: loaded)
        _proxyPortText = State(initialValue: loaded.proxyServerPort == 0 ? "" : String(loaded.proxyServerPort))
        _listenPortText = State(initialValue: loaded.listenPort == 0 ? "" : String(loaded.listenPort))
    }

    var body: some View {
        Form {
            connectionSection
            encryptionSection
            advancedSection
            controlSection
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "绑定地址不是本机回环地址",
            isPresented: $showExposureWarning
        ) {
            Button("仍然启动", role: .destructive) {
                performStart()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前绑定 \(config.bindAddress)，局域网内其他设备可能访问该代理。")
        }
        .onAppear {
            updateStatus()
            presentAutoStartErrorIfNeeded()
        }
        .onDisappear {
            saveNow()
        }
        .onReceive(statusTimer) { _ in updateStatus() }
        .onChange(of: notices.autoStartError) { _ in
            presentAutoStartErrorIfNeeded()
        }
        .onChange(of: config) { _ in
            scheduleAutosave()
        }
        .onChange(of: proxyPortText) { _ in
            if let port = parsedPort(proxyPortText) {
                config.proxyServerPort = port
            }
        }
        .onChange(of: listenPortText) { _ in
            if let port = parsedPort(listenPortText) {
                config.listenPort = port
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            // `terminate` from the menu does not necessarily trigger
            // onDisappear/willResignActive, so save the latest edits here.
            saveNow()
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section("连接设置") {
            LabeledContent("代理服务器") {
                HStack(spacing: 4) {
                    TextField(text: $config.proxyServerAddress, prompt: Text("地址")) {
                        EmptyView()
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)

                    Text(":").foregroundColor(.secondary)

                    TextField(text: $proxyPortText, prompt: Text("端口")) {
                        EmptyView()
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                }
            }
            LabeledContent("本地绑定") {
                HStack(spacing: 4) {
                    TextField(text: $config.bindAddress, prompt: Text("地址")) {
                        EmptyView()
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)

                    Text(":").foregroundColor(.secondary)

                    TextField(text: $listenPortText, prompt: Text("端口")) {
                        EmptyView()
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                }
            }

            if isExposingToLAN {
                Label("当前绑定地址可能允许局域网访问", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Encryption Section

    private var encryptionSection: some View {
        Section("加密设置") {
            VStack(alignment: .leading, spacing: 6) {
                Text("RSA 公钥 (PEM)").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $config.rsaPublicKey)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .scrollContentBackground(.visible)
            }

            Picker("加密算法", selection: $config.cipher) {
                ForEach(ConfigModel.supportedCiphers, id: \.self) { cipher in
                    Text(cipher).tag(cipher)
                }
            }

            LabeledContent("Auth Key") {
                HStack(spacing: 6) {
                    Group {
                        if isAuthKeyVisible {
                            TextField(text: $config.authKey, prompt: Text("可选")) {
                                EmptyView()
                            }
                        } else {
                            SecureField(text: $config.authKey, prompt: Text("可选")) {
                                EmptyView()
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .privacySensitive()

                    Button {
                        isAuthKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAuthKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(isAuthKeyVisible ? "隐藏 Auth Key" : "显示 Auth Key")
                    .accessibilityLabel(isAuthKeyVisible ? "隐藏 Auth Key" : "显示 Auth Key")
                }
                .frame(maxWidth: 240)
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section("高级设置") {
            HStack {
                Text("超时 (秒)")
                Spacer()
                Stepper(value: $config.timeout, in: 30...600, step: 10) {
                    Text("\(config.timeout)")
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            HStack {
                Text("工作线程")
                Spacer()
                Stepper(value: $config.workers, in: 1...16) {
                    Text("\(config.workers)")
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Control Section

    private var controlSection: some View {
        Section {
            HStack(spacing: 16) {
                Button(action: toggleProxy) {
                    Label(
                        isRunning ? "停止" : "启动",
                        systemImage: isRunning ? "stop.fill" : "play.fill"
                    )
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .red : .green)

                Spacer()

                StatusDot(isRunning: isRunning)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: $appSettings.autoStart) {
                Text("应用启动时自动运行")
            }
            .onChange(of: appSettings.autoStart) { _ in
                appSettings.save()
            }

            if isRunning {
                Label("代理运行中，修改配置将在下次启动时生效。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func toggleProxy() {
        if isRunning {
            stopProxy()
        } else {
            startProxy()
        }
    }

    private func startProxy() {
        if let message = validateForStart() {
            errorMessage = message
            showError = true
            return
        }

        if isExposingToLAN {
            showExposureWarning = true
            return
        }

        performStart()
    }

    private func performStart() {
        // Persist non-secret settings and the Auth Key. If the Keychain is
        // temporarily unavailable, the in-memory key is still used for this
        // session and the save error is shown to the user.
        _ = saveConfig(showErrors: true)

        switch bridge.start(config: config) {
        case .success:
            isRunning = true
            statusMessage = "运行中"
        case .failure(let err):
            errorMessage = err.localizedDescription
            showError = true
        }
    }

    private func validateForStart() -> String? {
        guard let proxyPort = parsedPort(proxyPortText) else {
            return "代理服务器端口必须是 1–65535 的整数。"
        }
        guard let listenPort = parsedPort(listenPortText) else {
            return "本地监听端口必须是 1–65535 的整数。"
        }

        config.proxyServerPort = proxyPort
        config.listenPort = listenPort
        config = config.normalized()
        return config.validationError()
    }

    private var isExposingToLAN: Bool {
        let bind = config.bindAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bind.isEmpty else { return false }
        return bind != "::1" && bind != "localhost" && !bind.hasPrefix("127.")
    }

    private func stopProxy() {
        switch bridge.stop() {
        case .success:
            isRunning = false
            statusMessage = "已停止"
        case .failure(let err):
            errorMessage = err.localizedDescription
            showError = true
        }
    }

    @discardableResult
    private func saveConfig(showErrors: Bool = false) -> Bool {
        syncPortsFromText()
        do {
            try config.save()
            return true
        } catch {
            if showErrors {
                errorMessage = "保存配置失败：\(error.localizedDescription)"
                showError = true
            }
            return false
        }
    }

    private func syncPortsFromText() {
        if let port = parsedPort(proxyPortText) {
            config.proxyServerPort = port
        }
        if let port = parsedPort(listenPortText) {
            config.listenPort = port
        }
    }

    private func parsedPort(_ text: String) -> UInt16? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(trimmed), port > 0 else { return nil }
        return port
    }

    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        let work = DispatchWorkItem {
            _ = saveConfig()
        }
        autosaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func cancelAutosave() {
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
    }

    private func saveNow() {
        cancelAutosave()
        appSettings.save()
        _ = saveConfig()
    }

    private func updateStatus() {
        isRunning = bridge.status()
        statusMessage = isRunning ? "运行中" : "空闲"
    }

    private func presentAutoStartErrorIfNeeded() {
        guard let message = notices.autoStartError, !message.isEmpty else { return }
        notices.autoStartError = nil
        errorMessage = "自动启动失败：\(message)"
        showError = true
    }
}

// MARK: - Status Dot

private struct StatusDot: View {
    let isRunning: Bool

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.gray)
            .frame(width: 10, height: 10)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(minWidth: 450, minHeight: 500)
}

import SwiftUI

// MARK: - Supported Ciphers

private let supportedCiphers = [
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

// MARK: - ContentView

struct ContentView: View {
    @State private var config: ConfigModel
    @State private var isRunning = false
    @State private var statusMessage = "空闲"
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isAuthKeyVisible = false

    @ObservedObject private var notices = AppNotices.shared

    private let bridge = RustBridge.shared
    private let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init() {
        _config = State(initialValue: ConfigModel.load() ?? ConfigModel())
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
        .onAppear {
            updateStatus()
            presentAutoStartErrorIfNeeded()
        }
        .onDisappear {
            _ = saveConfig()
        }
        .onReceive(statusTimer) { _ in updateStatus() }
        .onChange(of: notices.autoStartError) { _ in
            presentAutoStartErrorIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            _ = saveConfig()
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

                    TextField(text: portBinding($config.proxyServerPort), prompt: Text("端口")) {
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

                    TextField(text: portBinding($config.listenPort), prompt: Text("端口")) {
                        EmptyView()
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                }
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
                ForEach(supportedCiphers, id: \.self) { cipher in
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

            Toggle(isOn: $config.autoStart) {
                Text("应用启动时自动运行")
            }
            .onChange(of: config.autoStart) { _ in
                _ = saveConfig(showErrors: true)
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

// MARK: - Port Binding Helper

/// Creates a string binding that maps to a UInt16 value binding.
/// This avoids the macOS `TextField` title-as-label issue where placeholders
/// don't disappear after entering a value.
private func portBinding(_ number: Binding<UInt16>) -> Binding<String> {
    Binding<String>(
        get: { number.wrappedValue == 0 ? "" : "\(number.wrappedValue)" },
        set: {
            if let value = UInt16($0.filter(\.isNumber)) {
                number.wrappedValue = value
            }
        }
    )
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

import SwiftUI

struct ProxySettingsView: View {
    @EnvironmentObject private var appState: LauncherAppState

    @State private var isEditing = false
    @State private var isChecking = false
    @State private var connectivityResult: ProxyProbeResult?
    @State private var fileExists = false
    private let connectivityService = ProxyConnectivityService()

    private var portText: Binding<String> {
        Binding(
            get: { String(appState.proxyConfigDraft.proxy.port) },
            set: { input in
                let digits = input.filter { $0.isNumber }
                guard !digits.isEmpty else { return }
                if let value = Int(digits) {
                    appState.proxyConfigDraft.proxy.port = min(max(value, 1), 65535)
                }
            }
        )
    }

    /// 模型映射总开关:切换即写入 proxy_config.json(与首页行为一致)
    private var modelRoutingToggleBinding: Binding<Bool> {
        Binding(
            get: { appState.proxyConfigDraft.mitm?.modelRoutingEnabled ?? false },
            set: { newValue in
                if appState.proxyConfigDraft.mitm != nil {
                    appState.proxyConfigDraft.mitm?.modelRoutingEnabled = newValue
                } else {
                    appState.proxyConfigDraft.mitm = .init(modelRoutingEnabled: newValue)
                }
                appState.saveProxyConfig()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text("Proxy Settings")
                            .font(.title2)
                            .bold()
                    }
                    Text("Configure the upstream SOCKS5/HTTP proxy node. All target apps share this configuration.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }

                // Settings card
                VStack(alignment: .leading, spacing: 16) {
                    headerView
                    Divider()
                    proxySettingsView
                    Divider()
                    featuresView
                    statusView
                    Divider()
                    fileInfoView
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )

                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            appState.loadProxyConfigIfNeeded()
            refreshFileState()
            checkConnectivity()
        }
        .onChange(of: appState.proxyConfigDraft) { _ in
            refreshFileState()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectivityDotColor)
                .frame(width: 8, height: 8)
            Text(connectivityText)
                .font(.system(size: 13))
                .foregroundStyle(connectivityTextColor)
            Spacer()
            detectButton
            if isEditing {
                cancelButton
                saveButton
            } else {
                editButton
            }
        }
    }

    // MARK: - Proxy settings

    private var proxySettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                settingRow(label: "Type", width: 72) {
                    TextField("SOCKS5/HTTP", text: $appState.proxyConfigDraft.proxy.type)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                settingRow(label: "Host", width: 72) {
                    TextField("127.0.0.1", text: $appState.proxyConfigDraft.proxy.host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                settingRow(label: "Port", width: 72) {
                    TextField("7897", text: portText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: 100)
                }
            } else {
                readOnlyRow(label: "Type", value: appState.proxyConfigDraft.proxy.type)
                readOnlyRow(label: "Host", value: appState.proxyConfigDraft.proxy.host)
                readOnlyRow(label: "Port", value: String(appState.proxyConfigDraft.proxy.port))
            }
        }
    }

    // MARK: - Features

    private var featuresView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                settingRow(label: "Log level", width: 72) {
                    Picker("", selection: $appState.proxyConfigDraft.logLevel) {
                        Text("error").tag("error")
                        Text("warn").tag("warn")
                        Text("info").tag("info")
                        Text("debug").tag("debug")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                settingRow(label: "Model mapping", width: 72) {
                    Toggle("", isOn: Binding(
                        get: { appState.proxyConfigDraft.mitm?.modelRoutingEnabled ?? false },
                        set: { newValue in
                            if appState.proxyConfigDraft.mitm != nil {
                                appState.proxyConfigDraft.mitm?.modelRoutingEnabled = newValue
                            } else {
                                appState.proxyConfigDraft.mitm = .init(modelRoutingEnabled: newValue)
                            }
                        }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                settingRow(label: "FakeIP", width: 72) {
                    Toggle("", isOn: $appState.proxyConfigDraft.fakeIP.enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                settingRow(label: "CIDR", width: 72) {
                    TextField("198.18.0.0/15", text: $appState.proxyConfigDraft.fakeIP.cidr)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .disabled(!appState.proxyConfigDraft.fakeIP.enabled)
                }
            } else {
                // 模型映射开关直接暴露:切换即保存,无需进入编辑模式
                settingRow(label: "Model mapping", width: 72) {
                    Toggle("", isOn: modelRoutingToggleBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help("The local gateway restarts automatically after you switch")
                }
                readOnlyRow(label: "Log level", value: appState.proxyConfigDraft.logLevel)
                readOnlyRow(label: "FakeIP", value: appState.proxyConfigDraft.fakeIP.enabled ? "On · \(appState.proxyConfigDraft.fakeIP.cidr)" : "Off")
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        if let msg = appState.configStatusMessage {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.green)
                Text(msg).font(.system(size: 12)).foregroundStyle(.green).lineLimit(1)
            }
        }
        if let err = appState.configErrorMessage {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red)
                Text(err).font(.system(size: 12)).foregroundStyle(.red).lineLimit(1)
            }
        }
    }

    // MARK: - File info

    private var fileInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: fileExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(fileExists ? .green : .red)
                Text(fileExists ? "Configuration file present" : "Configuration file missing")
                    .font(.system(size: 12))
                    .foregroundStyle(fileExists ? .green : .red)
            }
            Text(FileSystemPaths.userProxyConfigFile.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // MARK: - Helpers

    private func readOnlyRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func settingRow<Content: View>(label: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: width, alignment: .leading)
            content()
        }
    }

    // MARK: - Buttons

    private var detectButton: some View {
        Button(action: { checkConnectivity() }) {
            ButtonLabel(
                icon: isChecking ? "hourglass" : "antenna.radiowaves.left.and.right",
                text: isChecking ? "Detecting" : "Detect"
            )
        }
        .primaryActionStyle()
        .disabled(isChecking)
    }

    private var editButton: some View {
        Button(action: { isEditing = true }) {
            ButtonLabel(icon: "pencil", text: "Edit")
        }
        .secondaryActionStyle()
    }

    private var cancelButton: some View {
        Button(action: {
            appState.loadProxyConfig()
            isEditing = false
        }) {
            ButtonLabel(icon: "xmark", text: "Cancel")
        }
        .secondaryActionStyle()
    }

    private var saveButton: some View {
        Button(action: {
            appState.saveProxyConfig()
            isEditing = false
        }) {
            ButtonLabel(icon: "square.and.arrow.down", text: "Save")
        }
        .primaryActionStyle()
    }

    // MARK: - Connectivity

    private var currentConnectivity: ProxyProbeResult? { connectivityResult }

    private var connectivityDotColor: Color {
        guard let r = currentConnectivity else { return .gray }
        return r.isOK ? .green : .red
    }

    private var connectivityText: String {
        guard let r = currentConnectivity else { return "Not checked" }
        return r.isOK ? "Connected" : "Error"
    }

    private var connectivityTextColor: Color {
        guard let r = currentConnectivity else { return .secondary }
        return r.isOK ? .green : .red
    }

    private func checkConnectivity() {
        guard !isChecking else { return }
        let cfg = appState.proxyConfigDraft.proxy
        isChecking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = connectivityService.probe(host: cfg.host, port: cfg.port, type: cfg.type)
            DispatchQueue.main.async {
                connectivityResult = r
                isChecking = false
            }
        }
    }

    private func refreshFileState() {
        fileExists = FileManager.default.fileExists(atPath: FileSystemPaths.userProxyConfigFile.path)
    }
}

import AppKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: LauncherAppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedTab) {
                Section("Core features") {
                    NavigationLink(value: LauncherTab.overview) {
                        Label("Run Status", systemImage: "gauge.with.needle")
                    }
                    NavigationLink(value: LauncherTab.proxySettings) {
                        Label("Proxy Settings", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink(value: LauncherTab.modelRouting) {
                        Label("Model mapping", systemImage: "arrow.triangle.branch")
                    }
                }

                Section("Maintenance & Settings") {
                    NavigationLink(value: LauncherTab.diagnostics) {
                        Label("System Diagnostics", systemImage: "stethoscope")
                    }
                    NavigationLink(value: LauncherTab.settings) {
                        Label("Preferences", systemImage: "gearshape")
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarVersionFooter()
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch appState.selectedTab {
            case .overview:
                OverviewView()
            case .proxySettings:
                ProxySettingsView()
            case .modelRouting:
                ModelRoutingView()
            case .diagnostics:
                DiagnosticsView()
            case .settings:
                SettingsView()
            }
        }
    }
}

// MARK: - Sidebar Version Footer

private struct SidebarVersionFooter: View {
    @EnvironmentObject private var appState: LauncherAppState

    private var updateInfo: ReleaseUpdateInfo? {
        guard let info = appState.releaseUpdateInfo,
              info.isUpdateAvailable,
              !appState.isReleaseVersionIgnored(info.latestVersion)
        else { return nil }
        return info
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.3)

            if let info = updateInfo {
                Menu {
                    if let notes = info.notes, !notes.isEmpty {
                        Text("[Changelog]\n" + notes)
                            .font(.system(.caption, design: .monospaced))
                    }
                    Divider()
                    Button("Open download page") {
                        if let urlString = info.downloadURL,
                           let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Ignore this version") {
                        appState.ignoreCurrentReleaseUpdate()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("v\(appState.launcherVersionText) -> v\(info.latestVersion)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            } else {
                HStack {
                    Spacer()
                    Text("v\(appState.launcherVersionText)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .background(.bar)
    }
}

// MARK: - Overview

private struct OverviewView: View {
    @EnvironmentObject private var appState: LauncherAppState
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var showCleanEnvironmentConfirm = false
    @State private var showClearLogsConfirm = false
    @State private var justCopiedLogs = false
    @State private var isRefreshHovered = false
    @State private var isRefreshing = false
    @State private var proxyConnected = false

    private var refreshButtonFg: Color {
        if isRefreshing || isRefreshHovered { return .blue }
        return Color.primary.opacity(0.8)
    }
    private var refreshButtonBg: Color {
        if isRefreshing { return Color.blue.opacity(0.18) }
        if isRefreshHovered { return Color.blue.opacity(0.12) }
        return Color.primary.opacity(0.08)
    }

    private var isOverviewTabActive: Bool {
        appState.selectedTab == .overview
    }

    private var statusColor: Color {
        switch appState.status {
        case .running, .patchedReady:
            return .green
        case .patching, .launching, .cleaning:
            return .blue
        case .targetAppInstalled, .patchedAppMissing, .patchedAppOutdated:
            return .orange
        case .targetAppMissing, .targetAppUnsupportedVersion, .error, .repairRequired:
            return .red
        }
    }

    @ViewBuilder
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Run Status")
                            .font(.title) // title 保持原生 22pt，但副标题放大
                            .bold()
                        Text("Manage proxy injection status and core resource usage")
                            .font(.body) // 从 subheadline 放大到 body (13pt)，整体大气
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            // 首页顶栏暂不展示 Claude Code / Codex 入口
                            let apps = TargetApp.allCases.filter { $0 != .claudeCode && $0 != .codex }
                            ForEach(Array(apps.enumerated()), id: \.element.id) { idx, app in
                                let isComingSoon = (app.sourceType == nil)
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        appState.selectedApp = app
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: app.iconName)
                                            .font(.system(size: 11))
                                        Text(app.displayName)
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(appState.selectedApp == app ? Color.blue.opacity(0.20) : Color.primary.opacity(0.08))
                                    .foregroundStyle(appState.selectedApp == app ? .blue : .primary.opacity(0.75))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(appState.selectedApp == app ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.isRunningWorkflow || isComingSoon)
                                .opacity(isComingSoon ? 0.4 : 1.0)
                                .help(isComingSoon ? "Coming in a later version" : "")
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    // 核心运行环境卡片 — 始终显示
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "app.badge.checkmark.fill")
                                .foregroundStyle(.blue)
                            Text("Core runtime")
                                .font(.title3)

                            Spacer()

                            // Refresh button
                            Button(action: {
                                isRefreshing = true
                                appState.refresh()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    isRefreshing = false
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(refreshButtonFg)
                                    .padding(5)
                                    .background(refreshButtonBg)
                                    .clipShape(Circle())
                                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                    .animation(isRefreshing ? .linear(duration: 0.6).repeatCount(1, autoreverses: false) : .default, value: isRefreshing)
                            }
                            .buttonStyle(.plain)
                            .disabled(appState.isRunningWorkflow || isRefreshing)
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isRefreshHovered = hovering
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if isRefreshHovered {
                                    Text(isRefreshing ? "Refreshing..." : "Refresh status")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.regularMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .offset(y: 18)
                                        .fixedSize()
                                }
                            }

                            // 核心控制按钮
                            if appState.appInfo != nil {
                                HStack(spacing: 6) {
                                    if appState.status == .running {
                                        Button(action: { appState.stopPatchedAppOnly() }) {
                                            ButtonLabel(icon: "stop.circle", text: appState.selectedApp.targetType == .cliBinary ? "Terminate process" : "Close app")
                                        }
                                        .dangerActionStyle()
                                        .disabled(appState.isRunningWorkflow)

                                        patchedAppButton(label: "Repair app", disabled: appState.isRunningWorkflow || !proxyConnected)
                                        cleanEnvironmentButton
                                    } else if appState.status == .patchedReady {
                                        Button(action: { appState.launchPatchedAppOnly() }) {
                                            ButtonLabel(icon: "play.circle", text: appState.selectedApp.targetType == .cliBinary ? "Verify installation" : "Launch app")
                                        }
                                        .successActionStyle()
                                        .disabled(appState.isRunningWorkflow)

                                        patchedAppButton(label: "Repair app", disabled: appState.isRunningWorkflow || !proxyConnected)
                                        cleanEnvironmentButton
                                    } else {
                                        patchedAppButton(label: "Repair app", disabled: appState.isRunningWorkflow || !proxyConnected)
                                        cleanEnvironmentButton
                                    }
                                }
                            }
                        }

                        // 代理未连接时提示
                        if !proxyConnected && appState.appInfo != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                Text("Click Detect in Proxy Settings first to confirm the proxy is connected")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.top, 4)
                        }

                        if let app = appState.appInfo {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 32) {
                                    if appState.selectedApp.targetType != .cliBinary {
                                        InfoItem(icon: "tag", title: "Bundle ID", value: app.bundleIdentifier)
                                    }
                                    InfoItem(icon: "number", title: "Environment version", value: app.version)
                                }

                                Divider()
                                    .opacity(0.3)

                                InfoItem(
                                    icon: "checkmark.seal.fill",
                                    title: "Current environment status",
                                    value: appState.status.title,
                                    valueColor: statusColor,
                                    isMono: false,
                                    enableAction: false
                                )

                                ProxyStatusInfo(proxyConnected: $proxyConnected)

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .foregroundStyle(.purple)
                                        .frame(width: 14, alignment: .top)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Model mapping")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(appState.proxyConfigDraft.mitm?.modelRoutingEnabled == true ? "On" : "Off")
                                            .font(.body)
                                            .foregroundStyle(appState.proxyConfigDraft.mitm?.modelRoutingEnabled == true ? .green : .secondary)
                                    }
                                }

                                InfoItem(icon: "macwindow", title: "Original app path", value: app.appPath, isMono: true)

                                let isPatchedAppExists = FileManager.default.fileExists(atPath: FileSystemPaths.patchedApp.path)
                                InfoItem(
                                    icon: "lock.open",
                                    title: "Unlocked app path",
                                    value: isPatchedAppExists ? FileSystemPaths.patchedApp.path : "(not generated / cleaned up)",
                                    valueColor: isPatchedAppExists ? .primary : .secondary,
                                    isMono: true
                                )

                                let tokenDirPath = FileSystemPaths.appSupportRoot.appendingPathComponent("oauth_tokens").path
                                let tokenFiles = try? FileManager.default.contentsOfDirectory(atPath: tokenDirPath)
                                let hasTokenFiles = tokenFiles?.contains { $0.hasSuffix(".json") } == true

                                InfoItem(
                                    icon: "key",
                                    title: "Current authorization directory",
                                    value: hasTokenFiles ? tokenDirPath : "(not authorized)",
                                    valueColor: hasTokenFiles ? .primary : .secondary,
                                    isMono: true
                                )
                            }
                        } else {
                            VStack(spacing: 16) {
                                Spacer()
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                Text("Target app not detected")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("Install \(appState.selectedApp.displayName) first, then refresh")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 160)
                        }

                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 3)


                    }

                HStack(alignment: .top, spacing: 16) {
                    // 流程进度卡片
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "checklist")
                                .foregroundStyle(.orange)
                            Text("Progress")
                                .font(.title3)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(appState.workflowItems) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    workflowIcon(for: item.state)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 14.5, weight: .semibold)) // 由 body 放大到 14.5pt 加粗
                                            .foregroundStyle(item.state == .pending ? .secondary : .primary)
                                        if let detail = item.detail, !detail.isEmpty {
                                            Text(detail)
                                                .font(.subheadline) // 由 footnote 放大到 subheadline
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 3)

                    // 拟真终端实时日志卡片
                    VStack(spacing: 0) {
                        // 终端窗口控制条 (OneDark 风格精致标题栏)
                        HStack {
                            Image(systemName: "terminal")
                                .font(.footnote)
                                .foregroundStyle(Color(red: 0.65, green: 0.68, blue: 0.76))
                            
                            Spacer()
                            
                            Text("INTELLIGENT RUNTIME LOGS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.65, green: 0.68, blue: 0.76))
                            
                            Spacer()
                            
                            // 一键复制日志按钮
                            Button(action: {
                                let allLogs = appState.logLines.joined(separator: "\n")
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(allLogs, forType: .string)
                                justCopiedLogs = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    justCopiedLogs = false
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: justCopiedLogs ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 8))
                                    Text(justCopiedLogs ? "Copied" : "Copy log")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(justCopiedLogs ? .green : Color(red: 0.65, green: 0.68, blue: 0.76))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help("Copy all runtime logs")

                            // 清理日志按钮
                            Button(action: {
                                showClearLogsConfirm = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 8))
                                    Text("Clear logs")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(Color(red: 0.91, green: 0.49, blue: 0.50))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help("Clear the repair log and system log")
                            .confirmationDialog(
                                "Confirm log cleanup",
                                isPresented: $showClearLogsConfirm,
                                titleVisibility: .visible
                            ) {
                                Button("Confirm cleanup", role: .destructive) {
                                    appState.clearLogs()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This deletes the repair log and runtime log files. This cannot be undone.")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.16, green: 0.17, blue: 0.22)) // 经典暗色标题栏
                        
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(appState.logLines.enumerated()), id: \.offset) { entry in
                                        HStack(alignment: .top, spacing: 4) {
                                            Text("❯")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(Color(red: 0.38, green: 0.62, blue: 0.86).opacity(0.8))
                                            Text(entry.element)
                                                .font(.system(size: 13, weight: .regular, design: .monospaced)) // 终端日志由 12 放大到 13，彻底清晰无压力
                                                .foregroundStyle(logColor(for: entry.element))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textSelection(.enabled)
                                        }
                                        .id(entry.offset)
                                    }
                                }
                                .padding(12)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onChange(of: appState.logLines.count) { count in
                                guard count > 0 else { return }
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo(count - 1, anchor: .bottom)
                                }
                            }
                        }
                        .background(Color(red: 0.11, green: 0.12, blue: 0.16)) // 经典深钛金灰
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .frame(height: 360)

                Spacer(minLength: 10)
            }
            .padding(24)
        }
        .onAppear {
            Task { @MainActor in
                appState.refresh()
            }
        }

    }

    private var cleanEnvironmentButton: some View {
        Button(action: { showCleanEnvironmentConfirm = true }) {
            ButtonLabel(icon: "trash", text: "Clean environment")
        }
        .dangerActionStyle()
        .disabled(appState.isRunningWorkflow)
        .confirmationDialog(
            "Confirm environment cleanup",
            isPresented: $showCleanEnvironmentConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm cleanup", role: .destructive) {
                appState.cleanEnvironment()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if appState.selectedApp.targetType == .cliBinary {
                Text("This deletes the repair directory and symbolic link for \(appState.selectedApp.displayName) and restores the original binary (if a backup exists).")
            } else {
                Text("This deletes the unlocked app for \(appState.selectedApp.displayName) and its configuration files.")
            }
        }
    }

    private func patchedAppButton(label: String, disabled: Bool) -> some View {
        Button(action: { appState.patchOnly() }) {
            ButtonLabel(icon: "wrench", text: label)
        }
        .primaryActionStyle()
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }

    @ViewBuilder
    private func workflowIcon(for state: LaunchWorkflowStepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.gray.opacity(0.5))
        case .running:
            RotatingIcon()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func logColor(for line: String) -> Color {
        let upper = line.uppercased()
        if upper.contains("[ERROR]") || upper.contains("FAILED") || upper.contains("ERROR:") {
            return Color(red: 0.91, green: 0.49, blue: 0.50) // 柔和的亮红
        } else if upper.contains("[WARN]") || upper.contains("WARNING:") {
            return Color(red: 0.94, green: 0.80, blue: 0.56) // 亮色琥珀橙
        } else if upper.contains("[DEBUG]") {
            return Color(red: 0.53, green: 0.57, blue: 0.65) // 浅灰蓝
        } else if upper.contains("SUCCESS") || upper.contains("[INFO]") {
            return Color(red: 0.56, green: 0.80, blue: 0.62) // 柔和青葱绿
        }
        return Color(red: 0.85, green: 0.87, blue: 0.91) // 护眼灰白文本
    }
}

private struct RotatingIcon: View {
    @State private var degree = 0.0
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .foregroundStyle(.blue)
            .rotationEffect(.degrees(degree))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    degree = 360.0
                }
            }
    }
}

private struct InfoItem: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = .primary
    var isMono: Bool = false
    var enableAction: Bool = true

    @State private var isHovered = false
    @State private var justCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .top)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline) // 由 footnote 放大到 subheadline (12pt)，整体非常醒目大气
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Text(value)
                        .font(isMono ? .system(size: 12.5, design: .monospaced) : .body) // mono 由 11.5 放大到 12.5，普通值由 subheadline (12pt) 放大到 body (13pt) // 微调 mono 路径字体大小
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(value)
                    
                    if enableAction && isHovered && !value.isEmpty && !value.hasPrefix("(") {
                        HStack(spacing: 4) {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(value, forType: .string)
                                justCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    justCopied = false
                                }
                            }) {
                                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9))
                                    .foregroundStyle(justCopied ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help(justCopied ? "Copied" : "Copy path")
                            
                            if value.hasPrefix("/") {
                                Button(action: {
                                    let url = URL(fileURLWithPath: value)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }) {
                                    Image(systemName: "arrow.right.to.line.compact")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Proxy Status Info

private struct ProxyStatusInfo: View {
    @EnvironmentObject private var appState: LauncherAppState
    @Binding var proxyConnected: Bool

    @State private var lastResult: ProxyProbeResult?
    @State private var isChecking = false
    private let service = ProxyConnectivityService()

    private var proxyOK: Bool { lastResult?.isOK == true }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .top)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Proxy connectivity")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Circle()
                        .fill(lastResult == nil ? .gray : (proxyOK ? Color.green : Color.red))
                        .frame(width: 6, height: 6)

                    if let result = lastResult {
                        Text(result.isOK ? "Connected" : "Error")
                            .font(.caption)
                            .foregroundStyle(result.isOK ? Color.green : Color.red)
                    } else {
                        Text("Not checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: { check() }) {
                        ButtonLabel(icon: "antenna.radiowaves.left.and.right", text: isChecking ? "Detecting" : "Detect")
                    }
                    .primaryActionStyle()
                    .disabled(isChecking)
                }

                if let result = lastResult, !result.isOK, let error = result.error {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.red)
                        .lineLimit(1)
                }
            }
        }
        .onAppear { check() }
    }

    private func check() {
        guard !isChecking else { return }
        let cfg = appState.proxyConfigDraft.proxy
        isChecking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = service.probe(host: cfg.host, port: cfg.port, type: cfg.type)
            DispatchQueue.main.async {
                lastResult = r
                proxyConnected = r.isOK
                isChecking = false
            }
        }
    }
}

private struct MitmToggleRow: View {
    @EnvironmentObject private var appState: LauncherAppState

    private var isGemini: Bool { appState.selectedApp == .gemini }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(isGemini ? .gray : .purple)
                .frame(width: 14, alignment: .top)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Model mapping")
                        .font(.subheadline)
                        .foregroundStyle(isGemini ? Color.secondary.opacity(0.4) : Color.secondary)

                    Spacer()

                    if isGemini {
                        Text("Not supported")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { appState.proxyConfigDraft.mitm?.modelRoutingEnabled ?? false },
                            set: { newValue in
                                if appState.proxyConfigDraft.mitm != nil {
                                    appState.proxyConfigDraft.mitm?.modelRoutingEnabled = newValue
                                } else {
                                    appState.proxyConfigDraft.mitm = .init(modelRoutingEnabled: newValue)
                                }
                                appState.saveProxyConfig()
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.85)
                        .help("The local gateway restarts automatically after you switch")
                    }
                }

                Text(isGemini
                     ? "Gemini is a separate app channel and needs no model mapping"
                     : "Redirect AI API requests to the local translation proxy. The gateway restarts automatically after you switch.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}


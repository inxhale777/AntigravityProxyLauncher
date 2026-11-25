import Foundation
import AppKit

enum LauncherTab: Hashable {
    case overview
    case proxySettings
    case modelRouting
    case diagnostics
    case settings
}

struct MenuBarAppStatus {
    let app: TargetApp
    let isInstalled: Bool
    let isRunning: Bool
    let isPatched: Bool

    var statusText: String {
        if isRunning { return "Running" }
        if isPatched { return "Ready" }
        if isInstalled { return "Installed" }
        return "Not installed"
    }
}

@MainActor
final class LauncherAppState: ObservableObject {
    @Published var selectedTab: LauncherTab = .overview
    @Published var isActivated: Bool = false
    @Published var status: AppStatus = .targetAppMissing
    @Published var appInfo: AppInfo?
    @Published var workflowItems: [LaunchWorkflowItem] = LaunchWorkflowStep.allCases.map {
        LaunchWorkflowItem(id: $0, state: .pending, detail: nil)
    }
    @Published var logLines: [String] = []
    private var allAppLogs: [TargetApp: [String]] = [:]
    @Published var isRunningWorkflow = false
    @Published var proxyConfigDraft: ProxyConfig = .default
    @Published var configStatusMessage: String?
    @Published var configErrorMessage: String?
    @Published var modelRoutingErrorMessage: String?
    @Published var modelRoutingConfig: ModelRoutingConfig = .default
    private var hasLoadedModelRoutingConfigs = false
    private let modelRoutingService = ModelRoutingService()
    @Published var settingsDraft: AppSettings = .default
    @Published var settingsStatusMessage: String?
    @Published var settingsErrorMessage: String?
    @Published var launcherVersionText: String = LauncherAppState.resolveLauncherVersion()
    @Published var releaseUpdateInfo: ReleaseUpdateInfo?
    @Published var releaseUpdateStatusMessage: String?
    @Published var releaseUpdateErrorMessage: String?

    @Published var allAppStatuses: [TargetApp: MenuBarAppStatus] = [:]

    @Published var selectedApp: TargetApp = .antigravity {
        didSet {
            guard oldValue != selectedApp else { return }
            UserDefaults.standard.set(selectedApp.rawValue, forKey: "SelectedTargetApp")
            FileSystemPaths.activeApp = selectedApp
            launchService.resetForTargetChange()
            
            // 缓存旧应用的实时日志，并加载新应用的实时日志，实现应用级日志完全隔离
            allAppLogs[oldValue] = logLines
            logLines = allAppLogs[selectedApp] ?? []
            
            appendLog("---------- Switched to \(selectedApp.displayName) ----------")
            refresh()
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "SelectedTargetApp"),
           let app = TargetApp(rawValue: saved) {
            self.selectedApp = app
            FileSystemPaths.activeApp = app
        }

        launchService.onAppTerminated = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.appendLog("Patched app has quit")
                self.refresh()
            }
        }
    }

    private var hasLoadedProxyConfig = false
    private var lastReleaseCheckAt: Date?

    private let appDetectionService = AppDetectionService()
    private let patchService = PatchService()
    private let verificationService = PatchVerificationService()
    private let launchService = LaunchService()
    private let migrationService = MigrationService()
    private let proxyConfigService = ProxyConfigService()
    private let settingsService = AppSettingsService()
    private let patchedAppHealthService = PatchedAppHealthService()
    private let releaseUpdateService = ReleaseUpdateService()

    func refresh() {
        loadProxyConfig()
        loadModelRoutingConfigs()
        loadSettings()
        refreshAllAppStatuses()

        guard let app = appDetectionService.detectInstalledTargetApp() else {
            appInfo = nil
            status = .targetAppMissing
            return
        }

        appInfo = app

        switch patchedAppHealthService.evaluate(targetVersion: app.version) {
            case .missing:
                status = .patchedAppMissing
            case .ready:
                status = launchService.isPatchedAppRunning() ? .running : .patchedReady
            case .outdated:
                status = .patchedAppOutdated
            case .repairRequired(let message):
                status = .repairRequired(message)
        }
    }

    func launchSpecificApp(_ app: TargetApp) {
        selectedApp = app
        refresh()
        launchPatchedAppOnly()
    }

    func patchSpecificApp(_ app: TargetApp) {
        selectedApp = app
        refresh()
        patchOnly()
    }

    func stopSpecificApp(_ app: TargetApp) {
        selectedApp = app
        stopPatchedAppOnly()
        refreshAllAppStatuses()
    }

    func patchOnly() {
        guard !isRunningWorkflow else { return }
        isRunningWorkflow = true

        Task {
            // 修复前预检查：代理连通性、磁盘空间、目标 App 占用
            let cfg = proxyConfigDraft.proxy
            let probeResult: ProxyProbeResult = await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: ProxyConnectivityService().probe(host: cfg.host, port: cfg.port, type: cfg.type))
                }
            }
            if !probeResult.isOK {
                await MainActor.run {
                    appendLog("Repair aborted: proxy not connected (\(probeResult.summary)). Make sure the proxy works before repairing.")
                    status = .error("Proxy not connected: \(probeResult.summary)")
                    isRunningWorkflow = false
                }
                return
            }

            // 检查磁盘空间（需要至少 2GB）
            let diskCheckResult = await checkDiskSpace()
            if !diskCheckResult.ok {
                await MainActor.run {
                    appendLog("Repair aborted: \(diskCheckResult.message)")
                    status = .error(diskCheckResult.message)
                    isRunningWorkflow = false
                }
                return
            }

            await runWorkflow()
        }
    }

    private func checkDiskSpace() async -> (ok: Bool, message: String) {
        let result = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let values = try home.resourceValues(forKeys: [.volumeAvailableCapacityKey])
                    if let freeBytes = values.volumeAvailableCapacity {
                        let freeGB = Double(freeBytes) / 1_073_741_824.0
                        if freeGB < 2.0 {
                            cont.resume(returning: (false, "Not enough free disk space (\(String(format: "%.1f", freeGB)) GB left, at least 2 GB needed)"))
                            return
                        }
                    }
                    cont.resume(returning: (true, ""))
                } catch {
                    cont.resume(returning: (true, "")) // 无法检查时继续，不阻塞修复
                }
            }
        }
        return result
    }

    func launchPatchedAppOnly() {
        guard !isRunningWorkflow else { return }
        isRunningWorkflow = true

        let isCLI = selectedApp.targetType == .cliBinary
        appendLog(isCLI ? "Verifying the CLI installation..." : "Launching the patched app directly...")
        status = .launching

        Task {
            do {
                let cliOutput = try await launchService.launchPatchedApp(settings: settingsDraft)
                await MainActor.run {
                    if isCLI {
                        if let output = cliOutput, !output.isEmpty {
                            self.appendLog("\(self.selectedApp.displayName) version: \(output)")
                        }
                        self.appendLog("Verified: proxy injection for \(self.selectedApp.displayName) is ready. The \(self.selectedApp.executableName) command is available in a terminal.")
                        self.status = .patchedReady
                    } else {
                        self.appendLog("Launched successfully!")
                        self.status = .running
                    }
                    self.isRunningWorkflow = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("\(isCLI ? "Verify" : "Launch") failed: \(error.localizedDescription)")
                    LauncherLogger.error("Direct launch failed: \(error)")
                    self.status = .error("\(isCLI ? "Verify" : "Launch") failed: \(error.localizedDescription)")
                    self.isRunningWorkflow = false
                }
            }
        }
    }

    func stopPatchedAppOnly() {
        guard !isRunningWorkflow else { return }

        isRunningWorkflow = true
        appendLog("Closing the patched app...")

        Task {
            try? await runBlocking {
                self.launchService.stopManagedPatchedApp()
            }

            let stillRunning = await MainActor.run {
                self.launchService.isPatchedAppRunning()
            }

            if stillRunning {
                let message = "Failed to close: the patched app is still running"
                await MainActor.run {
                    self.appendLog(message)
                    self.status = .error(message)
                    self.isRunningWorkflow = false
                }
                return
            }

            await MainActor.run {
                self.appendLog("Patched app closed")
                self.isRunningWorkflow = false
                self.refresh()
            }
        }
    }

    func clearLogs() {
        logLines.removeAll()
        allAppLogs[selectedApp] = [] // 同步清空当前应用的日志缓存

        let fm = FileManager.default
        var clearedTargets: [String] = []

        do {
            if fm.fileExists(atPath: FileSystemPaths.patchLogFile.path) {
                try fm.removeItem(at: FileSystemPaths.patchLogFile)
                clearedTargets.append("Repair log")
            }

            // Clean up dylib per-process log files (antigravity_proxy.{pid}.log)
            let configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/antigravity")
            if let contents = try? fm.contentsOfDirectory(atPath: configDir.path) {
                let dylibLogs = contents.filter { $0.hasPrefix("antigravity_proxy.") && $0.hasSuffix(".log") }
                var removed = 0
                for file in dylibLogs {
                    let path = configDir.appendingPathComponent(file).path
                    // Only remove logs from processes that are no longer running
                    let pidStr = file
                        .replacingOccurrences(of: "antigravity_proxy.", with: "")
                        .replacingOccurrences(of: ".log", with: "")
                    if let pid = Int32(pidStr), pid > 0 {
                        if kill(pid, 0) != 0 {
                            // Process not running, safe to delete
                            try? fm.removeItem(atPath: path)
                            removed += 1
                        }
                    }
                }
                if removed > 0 {
                    clearedTargets.append("\(removed) dylib log files")
                }
            }

            if clearedTargets.isEmpty {
                appendLog("Logs cleared: no log files to delete were found")
            } else {
                appendLog("Logs cleared: \(clearedTargets.joined(separator: ", "))")
            }
        } catch {
            appendLog("Failed to clear logs: \(error.localizedDescription)")
        }
    }

    func cleanEnvironment() {
        guard !isRunningWorkflow else { return }
        
        appendLog("Cleaning the runtime environment (logs excluded)...")
        status = .cleaning
        isRunningWorkflow = true
        
        Task {
            do {
                try await runBlocking {
                    let fm = FileManager.default

                    let report: (String) -> Void = { msg in
                        Task { @MainActor in self.appendLog(msg) }
                    }

                    if FileSystemPaths.activeApp.targetType == .cliBinary {
                        // CLI cleanup: remove patched directory and restore original symlink
                        let cliDir = FileSystemPaths.patchedCLIDir
                        if fm.fileExists(atPath: cliDir.path) {
                            try fm.removeItem(at: cliDir)
                            report("CLI repair directory removed: \(cliDir.path)")
                        } else {
                            report("No CLI repair directory found, nothing to clean up")
                        }

                        // Restore original binary from backup if it exists
                        let targetPath = FileSystemPaths.targetApp
                        let backupPath = targetPath.path + ".original"
                        if fm.fileExists(atPath: backupPath) {
                            if fm.fileExists(atPath: targetPath.path) || (try? targetPath.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                                try fm.removeItem(at: targetPath)
                            }
                            try fm.copyItem(at: URL(fileURLWithPath: backupPath), to: targetPath)
                            report("Original \(FileSystemPaths.activeApp.displayName) binary restored: \(backupPath)")
                        }
                    } else {
                        if fm.fileExists(atPath: FileSystemPaths.patchedApp.path) {
                            try fm.removeItem(at: FileSystemPaths.patchedApp)
                            report("Patched app removed: \(FileSystemPaths.patchedApp.path)")
                        } else {
                            report("No patched app found, nothing to clean up")
                        }
                    }

                    let metaURL = FileSystemPaths.appSupportRoot.appendingPathComponent("patch_metadata.json")
                    if fm.fileExists(atPath: metaURL.path) {
                        try fm.removeItem(at: metaURL)
                        report("Metadata file removed: \(metaURL.path)")
                    }
                }
                
                await MainActor.run {
                    self.appendLog("Environment cleanup finished!")
                    self.isRunningWorkflow = false
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Cleanup failed: \(error.localizedDescription)")
                    self.status = .error("Cleanup failed: \(error.localizedDescription)")
                    self.isRunningWorkflow = false
                }
            }
        }
    }



    func loadProxyConfig() {
        do {
            proxyConfigDraft = try proxyConfigService.loadForEditor()
            configErrorMessage = nil
            hasLoadedProxyConfig = true
        } catch {
            // 兜底：加载失败时使用默认值，提示用户编辑保存
            proxyConfigDraft = .default
            configErrorMessage = nil
            configStatusMessage = "First run: edit the proxy configuration and save"
            appendLog("Proxy configuration initialized with defaults")
        }
    }

    func loadProxyConfigIfNeeded() {
        if !hasLoadedProxyConfig {
            loadProxyConfig()
        }
    }

    func loadModelRoutingConfigs() {
        do {
            modelRoutingConfig = try modelRoutingService.load()
            // 确保 Ollama / vLLM / LM Studio 三个本地模型服务卡片始终存在
            modelRoutingConfig.ensureBuiltinLocalProviders()
            modelRoutingErrorMessage = nil
            hasLoadedModelRoutingConfigs = true
        } catch {
            modelRoutingErrorMessage = "Failed to load model mapping: \(error.localizedDescription)"
            appendLog("Failed to load model mapping: \(error.localizedDescription)")
        }
    }

    func loadModelRoutingConfigIfNeeded() {
        if !hasLoadedModelRoutingConfigs {
            loadModelRoutingConfigs()
        }
    }

    /// Saves the model routing config.
    func saveCurrentModelRoutingConfig() {
        do {
            try modelRoutingService.save(modelRoutingConfig)
            modelRoutingErrorMessage = nil
            appendLog("Model mapping configuration saved.")
        } catch {
            modelRoutingErrorMessage = "Failed to save model mapping: \(error.localizedDescription)"
            appendLog("Failed to save model mapping: \(error.localizedDescription)")
        }
    }

    func saveProxyConfig() {
        do {
            let result = try proxyConfigService.saveForNextPatch(proxyConfigDraft)
            configStatusMessage = "Configuration saved"
            configErrorMessage = nil
            appendLog("Proxy configuration saved: \(result.userConfigPath)")
            // The Go gateway pins its upstream endpoint and routing mode at
            // launch, so saved changes only take effect after a restart. Do it
            // now instead of leaving the process dialing a dead port (every
            // request then fails as "502 Upstream error").
            ProxyManager.shared.restartIfRuntimeConfigChanged(to: proxyConfigDraft)
        } catch {
            configErrorMessage = "Failed to save configuration: \(error.localizedDescription)"
            appendLog("Failed to save proxy configuration: \(error.localizedDescription)")
        }
    }

    func clearConfigStatusMessage() {
        configStatusMessage = nil
    }

    func loadSettings() {
        do {
            var loadedSettings = try settingsService.load()

            if loadedSettings.googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadedSettings.googleOAuthClientID = OAuthConstants.bundledDefaultClientID
            }

            if loadedSettings.googleOAuthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadedSettings.googleOAuthClientSecret = OAuthConstants.bundledDefaultClientSecret
            }

            if loadedSettings.releaseFeedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadedSettings.releaseFeedURL = AppSettings.default.releaseFeedURL
            }

            settingsDraft = loadedSettings
            isActivated = loadedSettings.isActivated
            settingsErrorMessage = nil
            applyDockIconSetting()
            checkLauncherUpdates(manual: false)
        } catch {
            settingsErrorMessage = "Failed to load settings: \(error.localizedDescription)"
            appendLog("Failed to load settings: \(error.localizedDescription)")
        }
    }

    func saveSettings() {
        do {
            settingsDraft.googleOAuthClientID = settingsDraft.googleOAuthClientID
                .trimmingCharacters(in: .whitespacesAndNewlines)
            settingsDraft.googleOAuthClientSecret = settingsDraft.googleOAuthClientSecret
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try settingsService.save(settingsDraft)
            applyDockIconSetting()
            settingsStatusMessage = "Settings saved"
            settingsErrorMessage = nil
            appendLog("Settings saved: \(FileSystemPaths.settingsFile.path)")
            checkLauncherUpdates(manual: false)
        } catch {
            settingsErrorMessage = "Failed to save settings: \(error.localizedDescription)"
            settingsStatusMessage = nil
            appendLog("Failed to save settings: \(error.localizedDescription)")
        }
    }

    private let validActivationCodes: Set<String> = [
        "QUctN0syTS05WDRQ",
        "QUctM044US02VDJX",
        "QUctNUoxTC04UjNZ",
        "QUctMk05Sy00UDdO",
        "QUctOFEzVC02VzFK"
    ]

    func verifyActivation(code: String) -> (success: Bool, message: String) {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let encoded = Data(normalizedCode.utf8).base64EncodedString()
        if normalizedCode.isEmpty {
            return (false, "The activation code cannot be empty")
        }
        
        if validActivationCodes.contains(encoded) {
            settingsDraft.isActivated = true
            isActivated = true
            saveSettings()
            return (true, "Activated")
        } else {
            return (false, "Invalid activation code. Follow the author's WeChat account to get the correct one")
        }
    }

    func checkLauncherUpdates(manual: Bool, forceRefresh: Bool = false) {
        if !forceRefresh, !manual,
           let lastReleaseCheckAt,
           Date().timeIntervalSince(lastReleaseCheckAt) < 600 {
            return
        }

        let feedURL = settingsDraft.releaseFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if feedURL.isEmpty {
            if manual {
                releaseUpdateErrorMessage = "Enter the update information URL first"
                releaseUpdateStatusMessage = nil
            }
            return
        }

        let trustedHosts = settingsDraft.releaseFeedTrustedHosts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        releaseUpdateStatusMessage = "Checking for launcher updates..."
        releaseUpdateErrorMessage = nil
        lastReleaseCheckAt = Date()

        // Detect GitHub repo URL: supports "owner/repo", "github.com/owner/repo", "https://github.com/owner/repo"
        let githubRepo = parseGitHubRepo(from: feedURL)

        Task {
            do {
                let result: ReleaseUpdateInfo
                if let (owner, repo) = githubRepo {
                    result = try await releaseUpdateService.checkGitHubRepo(
                        owner: owner, repo: repo, currentVersion: launcherVersionText,
                        githubToken: settingsDraft.githubToken,
                        forceRefresh: forceRefresh
                    )
                } else {
                    result = try await releaseUpdateService.check(
                        currentVersion: launcherVersionText,
                        urlString: feedURL,
                        trustedHostPatterns: trustedHosts
                    )
                }
                releaseUpdateInfo = result

                if result.isUpdateAvailable {
                    if isReleaseVersionIgnored(result.latestVersion) {
                        releaseUpdateStatusMessage = "Reminder for version \(result.latestVersion) ignored"
                    } else {
                        releaseUpdateStatusMessage = "New version \(result.latestVersion) available"
                    }
                    appendLog("New launcher version available: \(result.latestVersion)")
                } else {
                    releaseUpdateStatusMessage = "Already up to date (\(result.currentVersion))"
                    appendLog("Version check complete: launcher is up to date")
                }
                releaseUpdateErrorMessage = nil
            } catch {
                if manual {
                    releaseUpdateErrorMessage = "Update check failed: \(error.localizedDescription)"
                }
                releaseUpdateStatusMessage = nil
                appendLog("Update check failed: \(error.localizedDescription)")
            }
        }
    }

    func isReleaseVersionIgnored(_ version: String) -> Bool {
        let ignored = settingsDraft.releaseIgnoredVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ignored.isEmpty else {
            return false
        }
        return ignored == version
    }

    func ignoreCurrentReleaseUpdate() {
        guard let latest = releaseUpdateInfo?.latestVersion, !latest.isEmpty else {
            return
        }

        settingsDraft.releaseIgnoredVersion = latest

        do {
            try settingsService.save(settingsDraft)
            settingsStatusMessage = "Update reminder for version \(latest) ignored"
            settingsErrorMessage = nil
            releaseUpdateStatusMessage = "Reminder for version \(latest) ignored"
            releaseUpdateErrorMessage = nil
            appendLog("Launcher update ignored: \(latest)")
        } catch {
            settingsErrorMessage = "Failed to save the ignored version: \(error.localizedDescription)"
            appendLog("Failed to save the ignored version: \(error.localizedDescription)")
        }
    }

    func clearIgnoredReleaseVersion() {
        let previous = settingsDraft.releaseIgnoredVersion
        guard !previous.isEmpty else {
            return
        }

        settingsDraft.releaseIgnoredVersion = ""

        do {
            try settingsService.save(settingsDraft)
            settingsStatusMessage = "Update reminders restored"
            settingsErrorMessage = nil
            releaseUpdateStatusMessage = "Update reminders restored"
            releaseUpdateErrorMessage = nil
            appendLog("Launcher update reminders restored")
        } catch {
            settingsDraft.releaseIgnoredVersion = previous
            settingsErrorMessage = "Failed to restore update reminders: \(error.localizedDescription)"
            appendLog("Failed to restore update reminders: \(error.localizedDescription)")
        }
    }


    func applyDockIconSetting() {
        if settingsDraft.hideDockIcon {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func refreshAllAppStatuses() {
        var statuses: [TargetApp: MenuBarAppStatus] = [:]
        for app in TargetApp.allCases {
            let previous = FileSystemPaths.activeApp
            FileSystemPaths.activeApp = app
            defer { FileSystemPaths.activeApp = previous }

            let isInstalled = appDetectionService.detectInstalledTargetApp() != nil
            let patchedExists: Bool = {
                if app.targetType == .cliBinary {
                    return FileManager.default.fileExists(atPath: FileSystemPaths.patchedCLIWrapper.path)
                }
                return FileManager.default.fileExists(atPath: FileSystemPaths.patchedApp.path)
            }()
            let isRunning = launchService.isPatchedAppRunning()

            statuses[app] = MenuBarAppStatus(
                app: app,
                isInstalled: isInstalled,
                isRunning: isRunning,
                isPatched: patchedExists
            )
        }
        allAppStatuses = statuses
    }

    private func runWorkflow() async {
        isRunningWorkflow = true
        resetWorkflow()
        status = .patching
        appendLog("Starting the repair flow")

        do {
            markStep(.detect, as: .running)
            guard let app = appDetectionService.detectInstalledTargetApp() else {
                markStep(.detect, as: .failed, detail: "Not found: \(selectedApp.defaultPath)")
                status = .targetAppMissing
                appendLog("Failed: original app not detected (\(selectedApp.displayName))")
                isRunningWorkflow = false
                return
            }
            appInfo = app
            markStep(.detect, as: .completed, detail: "\(app.version)")
            appendLog("Detected app version: \(app.version)")

            markStep(.migration, as: .running)
            try await runBlocking {
                try self.migrationService.migrateSandboxData()
            }
            markStep(.migration, as: .completed)
            appendLog("Data migration complete")

            markStep(.patch, as: .running)
            try await runBlocking {
                try self.patchService.preparePatchedBundle(onProgress: { message in
                    Task { @MainActor in
                        self.appendLog(message)
                    }
                })
            }
            markStep(.patch, as: .completed)
            appendLog("Patched bundle processed")

            markStep(.verify, as: .running)
            try await runBlocking {
                try self.verificationService.verifyPatchedResult()
            }
            markStep(.verify, as: .completed)
            appendLog("Repair result verified")

            markStep(.launch, as: .completed, detail: "Waiting for manual launch")
            status = .patchedReady
            appendLog("Repair complete. You can now launch the patched app.")
        } catch {
            markCurrentRunningStepFailed(with: error.localizedDescription)
            status = .error("Repair failed: \(error.localizedDescription)")
            appendLog("Failed: \(error.localizedDescription)")

        }

        isRunningWorkflow = false
    }

    private func runBlocking<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func resetWorkflow() {
        workflowItems = LaunchWorkflowStep.allCases.map {
            LaunchWorkflowItem(id: $0, state: .pending, detail: nil)
        }
    }

    private func markStep(_ step: LaunchWorkflowStep, as state: LaunchWorkflowStepState, detail: String? = nil) {
        guard let index = workflowItems.firstIndex(where: { $0.id == step }) else { return }
        workflowItems[index].state = state
        workflowItems[index].detail = detail
    }

    private func markCurrentRunningStepFailed(with detail: String) {
        guard let index = workflowItems.firstIndex(where: { $0.state == .running }) else { return }
        workflowItems[index].state = .failed
        workflowItems[index].detail = detail
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        logLines.append("[\(timestamp)] \(message)")
        if logLines.count > 1000 {
            logLines.removeFirst(logLines.count - 1000)
        }
        allAppLogs[selectedApp] = logLines // 同步将日志缓存更新到当前应用
    }

    /// Parse a GitHub repo URL into (owner, repo). Supports formats:
    /// - "owner/repo"
    /// - "github.com/owner/repo"
    /// - "https://github.com/owner/repo"
    private func parseGitHubRepo(from urlString: String) -> (String, String)? {
        var cleaned = urlString.trimmingCharacters(in: .whitespaces)
        // Strip protocol
        if let range = cleaned.range(of: "https://") {
            cleaned = String(cleaned[range.upperBound...])
        } else if let range = cleaned.range(of: "http://") {
            cleaned = String(cleaned[range.upperBound...])
        }
        // Strip host if present
        if cleaned.hasPrefix("github.com/") {
            cleaned = String(cleaned.dropFirst("github.com/".count))
        }
        // Strip trailing slash
        if cleaned.hasSuffix("/") {
            cleaned = String(cleaned.dropLast())
        }
        let parts = cleaned.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    nonisolated static func resolveLauncherVersion() -> String {
        // Try bundled version.txt first (release builds)
        if let url = Bundle.main.url(forResource: "version", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            let version = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { return version }
        }

        // Try Resources/version.txt relative to launcher root (DEBUG / dev builds)
        let resourcesVersionURL = FileSystemPaths.launcherRoot
            .appendingPathComponent("Resources/version.txt")
        if let content = try? String(contentsOf: resourcesVersionURL, encoding: .utf8) {
            let version = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { return version }
        }

        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty { return version }

        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !build.isEmpty { return build }

        return "0.1.0-dev"
    }
}

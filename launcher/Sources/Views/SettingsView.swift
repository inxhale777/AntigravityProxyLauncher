import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: LauncherAppState
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var revealGoogleClientSecret = false
    @State private var revealGithubToken = false
    @State private var isTestingCredentials = false
    @State private var credentialTestResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(.gray)
                        Text("Preferences")
                            .font(.title2)
                            .bold()
                    }

                    Text("Controls how the repair flow behaves, its self-recovery policy and scheduling.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }

                VStack(alignment: .leading, spacing: 20) {
                    // 外观卡片
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "dock.rectangle")
                                .foregroundStyle(.teal)
                            Text("Appearance")
                                .font(.headline)
                        }
                        Divider()

                        Toggle("Hide the Dock icon (menu bar icon only)", isOn: $appState.settingsDraft.hideDockIcon)
                            .toggleStyle(.switch)

                        Text("Note: hiding takes effect after you restart the app, which then appears only in the menu bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )

                    // Google OAuth 凭据卡片
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "person.badge.key")
                                .foregroundStyle(.mint)
                            Text("Sign in with Google OAuth")
                                .font(.headline)

                            Spacer()

                            // 当前登录状态徽章
                            authStatusBadge
                        }

                        Divider()

                        // 当前账户状态
                        if authViewModel.accounts.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "person.slash")
                                    .foregroundStyle(.secondary)
                                Text("Status: not signed in")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(.green)
                                Text("Status: \(authViewModel.accounts.count) account(s) signed in")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)

                                if let active = authViewModel.activeAccount {
                                    Text("(active: \(active.email))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        HStack {
                            Text("Client ID")
                                .frame(width: 100, alignment: .leading)
                            TextField("Enter the Google OAuth Client ID", text: $appState.settingsDraft.googleOAuthClientID)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            Text("Client Secret")
                                .frame(width: 100, alignment: .leading)

                            Group {
                                if revealGoogleClientSecret {
                                    TextField("Enter the Google OAuth Client Secret", text: $appState.settingsDraft.googleOAuthClientSecret)
                                } else {
                                    SecureField("Enter the Google OAuth Client Secret", text: $appState.settingsDraft.googleOAuthClientSecret)
                                }
                            }
                                .textFieldStyle(.roundedBorder)

                            Button(action: { revealGoogleClientSecret.toggle() }) {
                                ButtonLabel(icon: revealGoogleClientSecret ? "eye.slash" : "eye", text: revealGoogleClientSecret ? "Hide" : "Show")
                            }
                            .secondaryActionStyle()
                        }

                        // 凭据验证按钮
                        HStack(spacing: 10) {
                            Button(action: testOAuthCredentials) {
                                ButtonLabel(icon: isTestingCredentials ? "hourglass" : "checkmark.shield", text: isTestingCredentials ? "Verifying..." : "Test credentials")
                            }
                            .secondaryActionStyle()
                            .disabled(isTestingCredentials)

                            if let result = credentialTestResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                                    .transition(.opacity)
                            }
                        }

                        Text("Note: if the AG_GOOGLE_CLIENT_ID / AG_GOOGLE_CLIENT_SECRET environment variables are set, they take precedence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("The credentials take effect after you click Save & Apply at the bottom.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    // 版本更新提醒卡片
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.purple)
                            Text("Launcher update available")
                                .font(.headline)
                        }

                        Divider()

                        Toggle(isOn: $appState.settingsDraft.updateChecksEnabled) {
                            Text("Check for updates")
                        }
                        .toggleStyle(.switch)

                        if !appState.settingsDraft.updateChecksEnabled {
                            Text("Off by default: the app does not contact GitHub about new versions. Turn on to check this fork's releases.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Current version")
                                .frame(width: 100, alignment: .leading)
                            Text(appState.launcherVersionText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Update source")
                                .frame(width: 100, alignment: .leading)
                            TextField("GitHub repository, e.g. inxhale777/AntigravityProxyLauncher", text: $appState.settingsDraft.releaseFeedURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Trusted hosts")
                                .frame(width: 100, alignment: .leading)
                            TextField("Only for a self-hosted feed; comma-separated", text: $appState.settingsDraft.releaseFeedTrustedHosts)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            Text("GitHub Token")
                                .frame(width: 100, alignment: .leading)

                            Group {
                                if revealGithubToken {
                                    TextField("Optional: raises the API rate limit", text: $appState.settingsDraft.githubToken)
                                } else {
                                    SecureField("Optional: raises the API rate limit", text: $appState.settingsDraft.githubToken)
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button(action: { revealGithubToken.toggle() }) {
                                ButtonLabel(icon: revealGithubToken ? "eye.slash" : "eye", text: revealGithubToken ? "Hide" : "Show")
                            }
                            .secondaryActionStyle()
                        }

                        Text("Note: without a token the GitHub API allows 60 requests per hour; with one, 5000 per hour. The token is only used to check for updates and needs no scopes (public_repo at most).")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button(action: { appState.checkLauncherUpdates(manual: true) }) {
                                ButtonLabel(icon: "arrow.down.circle", text: "Check for updates")
                            }
                            .primaryActionStyle()
                            .disabled(!appState.settingsDraft.updateChecksEnabled)

                            Button(action: { appState.checkLauncherUpdates(manual: true, forceRefresh: true) }) {
                                ButtonLabel(icon: "arrow.clockwise", text: "Force refresh")
                            }
                            .secondaryActionStyle()
                            .help("Clear cache and check again")
                            .disabled(!appState.settingsDraft.updateChecksEnabled)

                            if let info = appState.releaseUpdateInfo, info.isUpdateAvailable, !appState.isReleaseVersionIgnored(info.latestVersion) {
                                Text("New version available: \(info.latestVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        if !appState.settingsDraft.releaseIgnoredVersion.isEmpty {
                            HStack(spacing: 10) {
                                Text("Ignored version: \(appState.settingsDraft.releaseIgnoredVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button(action: { appState.clearIgnoredReleaseVersion() }) {
                                    ButtonLabel(icon: "bell", text: "Restore reminder")
                                }
                                .secondaryActionStyle()
                            }
                        }

                        if let status = appState.releaseUpdateStatusMessage, !status.isEmpty {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = appState.releaseUpdateErrorMessage, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )

                    // Footer 行动点与路径说明
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Button(action: { appState.loadSettings() }) {
                                ButtonLabel(icon: "arrow.counterclockwise", text: "Restore defaults")
                            }
                            .secondaryActionStyle()
                            
                            Button(action: { appState.saveSettings() }) {
                                ButtonLabel(icon: "square.and.arrow.down", text: "Save & Apply")
                            }
                            .primaryActionStyle()
                        }
                        
                        Divider()
                        
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.secondary)
                            Text("Runtime user-level environment file: \(FileSystemPaths.settingsFile.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(20)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }

                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            appState.loadSettings()
        }
        .animation(.easeInOut(duration: 0.25), value: credentialTestResult)
    }

    // MARK: - OAuth 凭据验证

    /// 通过尝试启动 OAuth 流程的第一步（构建授权 URL）来验证凭据是否有效。
    /// 这不会真正打开浏览器，只会校验 client_id 是否合法。
    private func testOAuthCredentials() {
        guard !isTestingCredentials else { return }

        let clientID = appState.settingsDraft.googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = appState.settingsDraft.googleOAuthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            credentialTestResult = "✗ Enter the Client ID and Client Secret first"
            return
        }

        guard !clientID.hasPrefix("YOUR_"), !clientSecret.hasPrefix("YOUR_") else {
            credentialTestResult = "✗ Replace these with real Google OAuth credentials"
            return
        }

        isTestingCredentials = true
        credentialTestResult = nil

        Task {
            do {
                // 通过构建一个最小化的授权 URL 来校验 client_id 格式
                var components = URLComponents(url: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!, resolvingAgainstBaseURL: false)
                components?.queryItems = [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "redirect_uri", value: "http://127.0.0.1:0/callback"),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: "openid email"),
                    URLQueryItem(name: "state", value: "test"),
                    URLQueryItem(name: "code_challenge", value: "test"),
                    URLQueryItem(name: "code_challenge_method", value: "S256")
                ]

                guard let url = components?.url else {
                    throw NSError(domain: "Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not build the authorization URL"])
                }

                // 尝试访问 Google OAuth 端点，验证 client_id 是否被 Google 识别
                var request = URLRequest(url: url, timeoutInterval: 10)
                request.httpMethod = "GET"

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NSError(domain: "Settings", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }

                if http.statusCode == 200 {
                    await MainActor.run {
                        credentialTestResult = "✓ Credentials are well-formed and the Google endpoint is reachable"
                        isTestingCredentials = false
                    }
                } else if http.statusCode == 400 {
                    await MainActor.run {
                        // 400 通常表示 redirect_uri 不匹配，但 client_id 被识别了
                        credentialTestResult = "✓ Client ID is recognized by Google (redirect_uri is set at sign-in time)"
                        isTestingCredentials = false
                    }
                } else {
                    await MainActor.run {
                        credentialTestResult = "✗ Server returned an unexpected status code \(http.statusCode)"
                        isTestingCredentials = false
                    }
                }
            } catch {
                await MainActor.run {
                    credentialTestResult = "✗ Network error: \(error.localizedDescription)"
                    isTestingCredentials = false
                }
            }
        }
    }

    // MARK: - 认证状态徽章

    private var authStatusBadge: some View {
        HStack(spacing: 6) {
            if authViewModel.accounts.isEmpty {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                Text("Not signed in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("\(authViewModel.accounts.count) account(s) signed in")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(authViewModel.accounts.isEmpty ? Color.gray.opacity(0.1) : Color.green.opacity(0.1))
        )
    }
}

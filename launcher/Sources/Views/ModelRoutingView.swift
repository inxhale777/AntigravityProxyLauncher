import SwiftUI

struct ModelRoutingView: View {
    @EnvironmentObject private var appState: LauncherAppState
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isRestarting = false

    @State private var isModelRoutingExpanded = true
    @State private var isProvidersExpanded = true
    @State private var isRoutingRulesExpanded = true
    @State private var isLLMRouterExpanded = true

    private var isModelRoutingEnabled: Bool {
        appState.proxyConfigDraft.mitm?.modelRoutingEnabled ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if isModelRoutingEnabled {
                    modelRoutingBusinessSection
                    llmRouterSection
                    controlSection
                } else {
                    disabledBanner
                }
                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            appState.loadProxyConfigIfNeeded()
            appState.loadModelRoutingConfigIfNeeded()
        }
    }

    private var disabledBanner: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Model mapping is off")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Turn on \"Model mapping\" in \"Proxy Settings\" before configuring mapping rules.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Proxy Settings") {
                appState.selectedTab = .proxySettings
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text("Model mapping (Model Routing)")
                    .font(.title2)
                    .bold()
            }
            Text("Configure model translation rules to map the target app's AI API requests to third-party compatible providers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 32)
        }
    }

    // MARK: - 模型路由业务配置（接口厂家 + 映射规则 合并为一个大卡片）

    private var modelRoutingBusinessSection: some View {
        let enabledProvidersCount = appState.modelRoutingConfig.providers.filter(\.enabled).count
        let totalProvidersCount = appState.modelRoutingConfig.providers.count
        let rulesCount = appState.modelRoutingConfig.routingRules.count
        let currentRules = appState.modelRoutingConfig.routingRules

        return CollapsibleCard(
            icon: "arrow.triangle.2.circlepath",
            accentColor: .green,
            title: "Model routing configuration",
            subtitle: "Configure third-party API providers and the mapping from source to target models",
            badgeText: "\(enabledProvidersCount)/\(totalProvidersCount) providers · \(rulesCount) rules",
            isExpanded: $isModelRoutingExpanded
        ) {
            VStack(alignment: .leading, spacing: 18) {
                // 子区 1：接口厂家配置
                SubCollapsibleSection(
                    icon: "rectangle.stack.badge.person.crop",
                    accentColor: .green,
                    title: "Provider settings",
                    description: "Tick the providers you want to enable and set each one's API endpoint and API key. Scroll down if there are more than two rows.",
                    badgeText: "\(enabledProvidersCount) enabled",
                    isExpanded: $isProvidersExpanded
                ) {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                            ForEach($appState.modelRoutingConfig.providers) { $provider in
                                ProviderCard(provider: $provider)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                    .frame(maxHeight: 520)
                    .padding(.top, 4)
                }

                Divider()
                    .opacity(0.5)

                // 子区 2：模型路由映射规则
                SubCollapsibleSection(
                    icon: "arrow.left.arrow.right",
                    accentColor: .orange,
                    title: "Model routing rules",
                    description: "Set the source models to translate and pick the target provider and model. A rule applies as long as it exists; delete it to stop the mapping.",
                    badgeText: "\(rulesCount) rules",
                    isExpanded: $isRoutingRulesExpanded
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Header labels
                        HStack(spacing: 8) {
                            Text("Source model name to match")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                                .frame(width: 140, alignment: .leading)
                            Spacer().frame(width: 20)
                            Text("Target provider")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .leading)
                            Text("Target model")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                                .frame(width: 170, alignment: .leading)
                            Spacer().frame(width: 24)
                        }
                        .padding(.horizontal, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach($appState.modelRoutingConfig.routingRules) { $rule in
                                let ruleID = $rule.wrappedValue.id
                                RoutingRuleRow(
                                    rule: $rule,
                                    allProviders: appState.modelRoutingConfig.providers,
                                    onDelete: {
                                        appState.modelRoutingConfig.routingRules.removeAll { $0.id == ruleID }
                                    }
                                )
                                if ruleID != currentRules.last?.id {
                                    Divider().opacity(0.4)
                                }
                            }

                            Button(action: {
                                let newRule = ModelRoutingConfig.RoutingRule(
                                    sourceModelPattern: "",
                                    sourceDisplayName: "New rule",
                                    sourceType: "google",
                                    targetProviderID: nil,
                                    targetModel: nil,
                                    enabled: true
                                )
                                appState.modelRoutingConfig.routingRules.append(newRule)
                            }) {
                                HStack(spacing: 6) {
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                    Text("Add rule")
                                    Spacer()
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .innerPanelStyle()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - LLMRouter Section

    private var llmRouterSection: some View {
        let hasLLMRouterRules = appState.modelRoutingConfig.routingRules.contains { $0.targetProviderID == LLMRouterProviderID }
        let isRouterEnabled = appState.modelRoutingConfig.llmRouter?.enabled ?? false
        let ruleCount = appState.modelRoutingConfig.llmRouter?.rules.count ?? 0

        return CollapsibleCard(
            icon: "shuffle",
            accentColor: .purple,
            title: "LLM Router (keyword routing)",
            subtitle: "Routes requests to different target models by keywords in the prompt",
            badgeText: isRouterEnabled ? "Enabled · \(ruleCount) rules" : "Off",
            isExpanded: $isLLMRouterExpanded,
            headerTrailing: {
                Toggle("", isOn: Binding(
                    get: { appState.modelRoutingConfig.llmRouter?.enabled ?? false },
                    set: { isOn in
                        if isOn {
                            if appState.modelRoutingConfig.llmRouter == nil {
                                appState.modelRoutingConfig.llmRouter = ModelRoutingConfig.LLMRouterConfig()
                            }
                            appState.modelRoutingConfig.llmRouter?.enabled = true
                        } else {
                            appState.modelRoutingConfig.llmRouter?.enabled = false
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if !hasLLMRouterRules {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Set the target provider to \"LLM Router\" in the model routing rules above and requests go through the keyword routing subsystem.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if !isRouterEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Some rules already map to LLM Router, but this feature is off. Turn it on to route by keyword.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.purple)
                        Text("Matches keywords in the request prompt and routes to the target model; requests with no match use the default model below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isRouterEnabled {
                    // Default model section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default model (used when no keyword matches)")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Picker("Default provider", selection: Binding(
                                get: { appState.modelRoutingConfig.llmRouter?.defaultProviderID ?? "" },
                                set: { newID in
                                    appState.modelRoutingConfig.llmRouter?.defaultProviderID = newID
                                    if let p = appState.modelRoutingConfig.providers.first(where: { $0.id == newID && $0.enabled }),
                                       !p.models.isEmpty {
                                        appState.modelRoutingConfig.llmRouter?.defaultModel = p.models[0]
                                    } else {
                                        appState.modelRoutingConfig.llmRouter?.defaultModel = ""
                                    }
                                }
                            )) {
                                Text("Select provider").tag("")
                                ForEach(appState.modelRoutingConfig.providers.filter(\.enabled)) { p in
                                    Text(p.name).tag(p.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)

                            let defaultPID = appState.modelRoutingConfig.llmRouter?.defaultProviderID ?? ""
                            if let provider = appState.modelRoutingConfig.providers.first(where: { $0.id == defaultPID && $0.enabled }) {
                                Picker("Default model", selection: Binding(
                                    get: { appState.modelRoutingConfig.llmRouter?.defaultModel ?? "" },
                                    set: { appState.modelRoutingConfig.llmRouter?.defaultModel = $0 }
                                )) {
                                    Text("Select model").tag("")
                                    ForEach(provider.models, id: \.self) { m in
                                        Text(m).tag(m)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 200)
                            } else {
                                Spacer().frame(width: 200)
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                        )
                    }

                    Divider()
                        .opacity(0.5)

                    // Keyword rules
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyword routing rules")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)

                        // Header
                        HStack(spacing: 8) {
                            Text("Keywords (comma-separated)")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                                .frame(width: 200, alignment: .leading)
                            Text("Match mode")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                            Text("Target provider")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                            Text("Target model")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .leading)
                            Spacer().frame(width: 24)
                        }
                        .padding(.horizontal, 8)

                        VStack(alignment: .leading, spacing: 6) {
                            let rulesBinding = Binding<[ModelRoutingConfig.LLMRouterRule]>(
                                get: { appState.modelRoutingConfig.llmRouter?.rules ?? [] },
                                set: { appState.modelRoutingConfig.llmRouter?.rules = $0 }
                            )
                            let currentRules = appState.modelRoutingConfig.llmRouter?.rules ?? []
                            ForEach(rulesBinding) { $rule in
                                let ruleID = $rule.wrappedValue.id
                                LLMRouterRuleRow(
                                    rule: $rule,
                                    allProviders: appState.modelRoutingConfig.providers,
                                    onDelete: {
                                        appState.modelRoutingConfig.llmRouter?.rules.removeAll { $0.id == ruleID }
                                    }
                                )
                                if ruleID != currentRules.last?.id {
                                    Divider().opacity(0.3)
                                }
                            }

                            Button(action: {
                                appState.modelRoutingConfig.llmRouter?.rules.append(
                                    ModelRoutingConfig.LLMRouterRule()
                                )
                            }) {
                                HStack(spacing: 6) {
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                    Text("Add keyword rule")
                                    Spacer()
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .innerPanelStyle()
                    }
                }
            }
        }
    }

    // MARK: - Control Section

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(action: {
                    appState.modelRoutingConfig = .default
                    statusMessage = "Default mapping rules restored. Click Save to apply."
                }) {
                    ButtonLabel(icon: "arrow.counterclockwise", text: "Restore defaults")
                }
                .secondaryActionStyle()

                Button(action: { saveConfig() }) {
                    if isRestarting {
                        HStack(spacing: 3) {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                            Text("Restarting proxy...").font(.system(size: 11, weight: .bold))
                        }
                    } else {
                        ButtonLabel(icon: "square.and.arrow.down", text: "Save & Apply")
                    }
                }
                .primaryActionStyle()
                .disabled(isRestarting)

                Spacer()

                if let message = statusMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(message)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.green)
                }
                if let error = errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            }

            Divider()
                .opacity(0.5)

            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.secondary)
                Text("Model mapping configuration file: \(ModelRoutingService().configPath())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func saveConfig() {
        appState.saveCurrentModelRoutingConfig()

        if let err = appState.modelRoutingErrorMessage {
            errorMessage = "Save failed: \(err)"
            statusMessage = nil
            return
        }

        errorMessage = nil
        statusMessage = nil
        isRestarting = true
        ProxyManager.shared.restartProxy(reason: "routing rules saved") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let ok = ProxyManager.shared.healthCheck()
                isRestarting = false
                if ok {
                    statusMessage = "Routing rules saved. The proxy has been restarted."
                } else {
                    errorMessage = "Health check failed after the proxy restart. Check port 18081."
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    statusMessage = nil
                    errorMessage = nil
                }
            }
        }
    }
}

// MARK: - Collapsible Card

struct CollapsibleCard<HeaderTrailing: View, Content: View>: View {
    let icon: String
    let accentColor: Color
    let title: String
    let subtitle: String?
    let badgeText: String?
    @Binding var isExpanded: Bool
    @ViewBuilder let headerTrailing: () -> HeaderTrailing
    @ViewBuilder let content: () -> Content

    @State private var isHeaderHovered = false

    init(
        icon: String,
        accentColor: Color,
        title: String,
        subtitle: String? = nil,
        badgeText: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder headerTrailing: @escaping () -> HeaderTrailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.accentColor = accentColor
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self._isExpanded = isExpanded
        self.headerTrailing = headerTrailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                // Icon squircle badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 32, height: 32)

                // Title + Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)

                        if let badge = badgeText, !badge.isEmpty {
                            Text(badge)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.12))
                                .foregroundStyle(accentColor)
                                .clipShape(Capsule())
                        }
                    }

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Extra trailing controls (e.g. LLM Router Toggle switch)
                headerTrailing()

                // Chevron icon
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHeaderHovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            }
            .onHover { hovering in
                isHeaderHovered = hovering
            }

            // Body content when expanded
            if isExpanded {
                Divider()
                    .opacity(0.5)

                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Sub Collapsible Section

struct SubCollapsibleSection<Content: View>: View {
    let icon: String
    let accentColor: Color
    let title: String
    let description: String?
    let badgeText: String?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Sub-header clickable
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let badge = badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.1))
                        .foregroundStyle(accentColor)
                        .clipShape(Capsule())
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }

            if isExpanded {
                if let desc = description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }

                content()
                    .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Provider Card

struct ProviderCard: View {
    @Binding var provider: ModelRoutingConfig.ProviderConfig

    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testOK = false
    private let modelService = ModelListService()

    // Local model servers (ollama / vllm / llama.cpp) may not need an API key,
    // so only the endpoint is required to run a connectivity test.
    private var canTest: Bool { !provider.apiEndpoint.isEmpty }

    private var providerWebsite: URL? {
        switch provider.id {
        case "deepseek":    return URL(string: "https://platform.deepseek.com/api_keys")
        case "ofox":        return URL(string: "https://app.ofox.ai/")
        case "codebuddy":   return URL(string: "https://www.codebuddy.cn/")
        case "tokenrouter": return URL(string: "https://www.tokenrouter.com/docs/tokenrouter-feature-guide/")
        case "openrouter":  return URL(string: "https://openrouter.ai/keys")
        default:
            // 本地服务模板 id 形如 "local-ollama-xxxx"，按前缀匹配官网
            if provider.id.hasPrefix("local-ollama") { return URL(string: "https://ollama.com") }
            if provider.id.hasPrefix("local-vllm") { return URL(string: "https://docs.vllm.ai") }
            if provider.id.hasPrefix("local-lmstudio") { return URL(string: "https://lmstudio.ai") }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(provider.name)
                    .font(.headline)
                    .foregroundStyle(provider.enabled ? .primary : .secondary)
                if let url = providerWebsite {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .iconButtonStyle()
                    .help("Open \(provider.name) website")
                    .disabled(!provider.enabled)
                }
                Spacer()
                Toggle("", isOn: $provider.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            // 表单始终渲染，保持卡片大小一致；关闭时整体置灰且不可编辑
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("Endpoint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    TextField("api.provider.com", text: $provider.apiEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .disabled(!provider.enabled)
                        .onChange(of: provider.apiEndpoint) { _ in clearTestResult() }
                }

                HStack(spacing: 8) {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    SecureField("sk-xxxx", text: $provider.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .disabled(!provider.enabled)
                        .onChange(of: provider.apiKey) { _ in clearTestResult() }
                }

                HStack(spacing: 8) {
                    Text("API path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    TextField("/v1/chat/completions", text: Binding(
                        get: { provider.options["api_path"] ?? "" },
                        set: { newValue in
                            if newValue.isEmpty {
                                provider.options.removeValue(forKey: "api_path")
                            } else {
                                provider.options["api_path"] = newValue
                            }
                            clearTestResult()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .disabled(!provider.enabled)
                }

                HStack(spacing: 8) {
                    Text(" ")
                        .frame(width: 50, alignment: .leading)
                    Toggle("Auto-sync available models", isOn: Binding(
                        get: { provider.options["auto_models"] == "true" },
                        set: { newValue in
                            if newValue {
                                provider.options["auto_models"] = "true"
                            } else {
                                provider.options.removeValue(forKey: "auto_models")
                            }
                            clearTestResult()
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .disabled(!provider.enabled)
                    .help("Fetch the latest model list from the endpoint on launch or test")
                }

                HStack(spacing: 8) {
                    Text(" ")
                        .frame(width: 50, alignment: .leading)
                    Toggle("Prompt compatibility mode", isOn: Binding(
                        get: { provider.options["sanitize_system_prompt"] == "true" },
                        set: { newValue in
                            if newValue {
                                provider.options["sanitize_system_prompt"] = "true"
                            } else {
                                provider.options.removeValue(forKey: "sanitize_system_prompt")
                            }
                            clearTestResult()
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .disabled(!provider.enabled)
                    .help("Moves the system instructions unchanged into a user message to bypass the upstream fingerprint check for third-party clients. Turn on if CodeBuddy / WorkBuddy returns \"Illegal API invocation from an unapproved channel\"; not needed for other providers")
                }

                // Test connection + fetch models + inline result
                HStack(spacing: 8) {
                    Text(" ")
                        .frame(width: 50, alignment: .leading)

                    Button(action: { testConnection() }) {
                        if isTesting {
                            HStack(spacing: 3) {
                                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                                Text("Testing...").font(.system(size: 11, weight: .bold))
                            }
                        } else {
                            ButtonLabel(icon: "play.circle", text: "Test connection")
                        }
                    }
                    .primaryActionStyle()
                    .disabled(!canTest || !provider.enabled || isTesting)
                    .help("Check API connectivity and fetch the list of available models")

                    if let result = testResult {
                        HStack(spacing: 4) {
                            Image(systemName: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 10))
                            Text(result)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .foregroundStyle(testOK ? .green : .red)
                    }

                    Spacer()
                }
            }
            .opacity(provider.enabled ? 1 : 0.55)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(provider.enabled ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(provider.enabled ? Color.green.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: provider.enabled)
    }

    private func clearTestResult() {
        testResult = nil
        testOK = false
    }

    /// Derive the models listing path from the chat completions api_path.
    private var modelsPath: String {
        if let apiPath = provider.options["api_path"], !apiPath.isEmpty {
            var parts = apiPath.split(separator: "/")
            if parts.count >= 2, parts.suffix(2).joined(separator: "/") == "chat/completions" {
                parts.removeLast(2)
                return "/" + parts.joined(separator: "/") + "/models"
            }
            if parts.count >= 1 {
                parts.removeLast()
                return "/" + parts.joined(separator: "/") + "/models"
            }
        }
        return "/v1/models"
    }

    private var authHeader: String {
        provider.options["auth_header"] ?? "Authorization"
    }

    private var authPrefix: String {
        provider.options["auth_prefix"] ?? "Bearer "
    }

    private var extraHeaders: [String: String] {
        guard let raw = provider.options["extra_headers"], !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return headers
    }

    private func testConnection() {
        guard canTest else { return }
        isTesting = true
        testResult = nil
        Task {
            do {
                let models = try await modelService.fetchModels(
                    endpoint: provider.apiEndpoint,
                    apiKey: provider.apiKey,
                    modelsPath: modelsPath,
                    authHeader: authHeader,
                    authPrefix: authPrefix,
                    extraHeaders: extraHeaders
                )
                await MainActor.run {
                    provider.models = models
                    testOK = true
                    testResult = "Connected, \(models.count) models found"
                    isTesting = false
                }
            } catch let error as ModelListService.ModelListError {
                if case .httpError(404) = error {
                    let apiPath = provider.options["api_path"] ?? "/v1/chat/completions"
                    let result = await modelService.probeEndpoint(
                        endpoint: provider.apiEndpoint,
                        apiKey: provider.apiKey,
                        apiPath: apiPath,
                        authHeader: authHeader,
                        authPrefix: authPrefix,
                        extraHeaders: extraHeaders
                    )
                    await MainActor.run {
                        testOK = result.ok
                        if result.ok {
                            let modelCount = provider.models.count
                            if modelCount > 0 {
                                testResult = "Connection works, \(modelCount) preset models available. The model list endpoint is unavailable (404)"
                            } else {
                                testResult = "Connection works, but the model list endpoint is unavailable (404). Enter the model names manually"
                            }
                        } else {
                            testResult = result.message
                        }
                        isTesting = false
                    }
                } else {
                    await MainActor.run {
                        testOK = false
                        testResult = "Connection failed: \(error.localizedDescription)"
                        isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    testOK = false
                    testResult = "Connection failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Source Models

private struct SourceModel: Identifiable {
    let pattern: String
    let displayName: String
    var id: String { pattern }
}

/// 映射规则可选的「源模型」候选（App 内部发起的模型名称）。
/// 与 `GeminiBuiltinModels`（2026-11-23 按官方文档与 App v2.34.0 模型表核对的清单）保持同步。
/// 这里统一使用不带档位后缀的「家族名」作为匹配模式：底层 `FindMatchingRule` 走子串匹配，
/// 因此 `claude-sonnet-5-5` 可覆盖 `claude-sonnet-5-5-low/medium/high/max` 全部档位。
private let sourceModels: [SourceModel] = [
    .init(pattern: "gemini-4-neon", displayName: "Gemini 4 Neon"),
    .init(pattern: "gemini-4-carbon", displayName: "Gemini 4 Carbon"),
    .init(pattern: "gemini-4-argon", displayName: "Gemini 4 Argon"),
    .init(pattern: "gemini-4-hydrogen", displayName: "Gemini 4 Hydrogen"),
    .init(pattern: "gemini-3.8-flash", displayName: "Gemini 3.8 Flash"),
    .init(pattern: "claude-opus-5-5", displayName: "Claude Opus 5.5"),
    .init(pattern: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5"),
    .init(pattern: "gpt-oss-120b", displayName: "GPT-OSS 120B"),
]

private func sourceModelDisplayName(for pattern: String) -> String {
    sourceModels.first(where: { $0.pattern == pattern })?.displayName ?? pattern
}

struct RoutingRuleRow: View {
    @Binding var rule: ModelRoutingConfig.RoutingRule
    let allProviders: [ModelRoutingConfig.ProviderConfig]
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Source model", selection: Binding(
                get: { rule.sourceModelPattern },
                set: { newValue in
                    rule.sourceModelPattern = newValue
                    rule.sourceDisplayName = sourceModelDisplayName(for: newValue)
                }
            )) {
                ForEach(sourceModels, id: \.pattern) { m in
                    Text(m.displayName).tag(m.pattern)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(width: 20)

            Picker("Provider", selection: Binding(
                get: {
                    if let pid = rule.targetProviderID,
                       let p = allProviders.first(where: { $0.id == pid }),
                       !p.enabled { return "" }
                    return rule.targetProviderID ?? ""
                },
                set: { newID in
                    rule.targetProviderID = newID.isEmpty ? nil : newID
                    if newID == LLMRouterProviderID {
                        rule.targetModel = nil
                    } else if let provider = allProviders.first(where: { $0.id == newID && $0.enabled }),
                       !provider.models.isEmpty {
                        rule.targetModel = provider.models[0]
                    } else {
                        rule.targetModel = nil
                    }
                }
            )) {
                Text("Select provider").tag("")
                ForEach(allProviders.filter(\.enabled)) { p in
                    Text(p.name).tag(p.id)
                }
                Divider()
                Text("LLM Router").tag(LLMRouterProviderID)
            }
            .labelsHidden()
            .frame(width: 130)

            if rule.targetProviderID == LLMRouterProviderID {
                Text("Keyword routing")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .frame(width: 170)
            } else if let pid = rule.targetProviderID,
               let provider = allProviders.first(where: { $0.id == pid && $0.enabled }) {
                Picker("Model", selection: Binding(
                    get: { rule.targetModel ?? "" },
                    set: { rule.targetModel = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Select model").tag("")
                    ForEach(provider.models, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            } else {
                Spacer().frame(width: 170)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
            }
            .iconButtonStyle()
            .help("Delete this rule")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// MARK: - LLMRouter Rule Row

struct LLMRouterRuleRow: View {
    @Binding var rule: ModelRoutingConfig.LLMRouterRule
    let allProviders: [ModelRoutingConfig.ProviderConfig]
    @State private var keywordsText: String = ""
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Keywords input
            TextField("frontend,React,Vue", text: $keywordsText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 200)
                .onChange(of: keywordsText) { newValue in
                    rule.keywords = newValue
                        .components(separatedBy: CharacterSet(charactersIn: ",，、;| \t\n"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }

            // Match mode
            Picker("Match mode", selection: $rule.matchMode) {
                Text("Any").tag("any")
                Text("All").tag("all")
            }
            .labelsHidden()
            .frame(width: 90)

            // Target provider
            Picker("Provider", selection: $rule.targetProviderID) {
                Text("Select").tag("")
                ForEach(allProviders.filter(\.enabled)) { p in
                    Text(p.name).tag(p.id)
                }
                Divider()
                Text("Gemini (built-in)").tag(GeminiBuiltinProviderID)
            }
            .labelsHidden()
            .frame(width: 120)

            // Target model
            if rule.targetProviderID == GeminiBuiltinProviderID {
                Picker("Model", selection: $rule.targetModel) {
                    Text("Select").tag("")
                    ForEach(GeminiBuiltinModels) { m in
                        Text(m.displayName).tag(m.id)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            } else if let provider = allProviders.first(where: { $0.id == rule.targetProviderID && $0.enabled }) {
                Picker("Model", selection: $rule.targetModel) {
                    Text("Select").tag("")
                    ForEach(provider.models, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            } else {
                Spacer().frame(width: 160)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
            }
            .iconButtonStyle()
            .help("Delete this rule")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .onAppear {
            keywordsText = rule.keywords.joined(separator: ",")
        }
    }
}

// MARK: - Preview

#if false
#Preview {
    ModelRoutingView()
        .environmentObject(LauncherAppState())
}
#endif

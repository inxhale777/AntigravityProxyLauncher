import Combine
import Foundation

/// 账户认证状态的 ViewModel。
///
/// 通过 Combine 订阅 `GoogleOAuthService` 的响应式发布者，
/// 所有状态变化（authState / loginFlowInfo / accounts）都会自动同步到 @Published 属性，
/// 无需在异步操作完成后手动调用 reloadState()。
@MainActor
final class AuthViewModel: ObservableObject {
    // MARK: - Published 状态（供 View 绑定）

    @Published private(set) var authState: AuthState = .notAuthenticated
    @Published private(set) var loginFlowState: LoginFlowState = .idle
    @Published private(set) var activeAccount: GoogleAccount?
    @Published private(set) var accounts: [GoogleAccount] = []
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var authURLString: String?
    @Published private(set) var isBusy = false

    // MARK: - 私有依赖

    private let oauthService: GoogleOAuthService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    init(oauthService: GoogleOAuthService = GoogleOAuthService()) {
        self.oauthService = oauthService
        oauthService.initialize()

        // 订阅 authState 变化 → 自动同步到 @Published
        oauthService.authStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.authState = newState
                // authState 变化时同时刷新账户列表（登录/登出时账户会改变）
                self.syncAccounts()
            }
            .store(in: &cancellables)

        // 订阅 loginFlowInfo 变化 → 自动同步登录流程状态
        oauthService.loginFlowInfoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                self.loginFlowState = info.state
                self.authURLString = info.authURL?.absoluteString
            }
            .store(in: &cancellables)

        // 初始化时同步一次账户列表
        syncAccounts()
    }

    // MARK: - 账户同步（内部）

    /// 从 oauthService 拉取最新的账户和 activeAccount，同步到 @Published。
    /// 仅在 authState 变化或明确需要时调用，View 层无需调用。
    private func syncAccounts() {
        do {
            accounts = try oauthService.getAccounts()
            activeAccount = try oauthService.getActiveAccount()
        } catch {
            // 账户加载失败不阻断 UI，只记录错误
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 对外操作

    func login() {
        guard !isBusy else { return }

        isBusy = true
        statusMessage = "Starting Google sign-in..."
        errorMessage = nil

        Task {
            do {
                _ = try await oauthService.login()
                // authState / loginFlowInfo 变化已通过 Combine 自动同步
                statusMessage = "Signed in"
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isBusy = false
        }
    }

    func cancelLogin() {
        oauthService.cancelLogin()
        statusMessage = "Sign-in cancelled"
        errorMessage = nil
        isBusy = false
        // loginFlowInfo 变化已通过 Combine 自动同步
    }

    func logout() {
        guard !isBusy else { return }

        isBusy = true
        Task {
            do {
                try oauthService.logout()
                statusMessage = "Signed out"
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isBusy = false
            // authState 变化已通过 Combine 自动同步
        }
    }

    func refreshAccessToken() {
        guard !isBusy else { return }

        isBusy = true
        statusMessage = "Validating the token..."
        errorMessage = nil

        Task {
            do {
                _ = try await oauthService.getValidAccessToken()
                statusMessage = "Token valid"
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isBusy = false
        }
    }

    func switchActiveAccount(to accountId: String) {
        guard !isBusy else { return }

        isBusy = true
        errorMessage = nil

        Task {
            do {
                try oauthService.setActiveAccount(accountId)
                statusMessage = "Account switched"
                syncAccounts() // 切换账户后手动刷新（不触发 authState 变化）
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isBusy = false
        }
    }

    // MARK: - 计算属性（供 View 使用）

    var activeAccountId: String? {
        activeAccount?.id
    }

    var authStateText: String {
        switch authState {
        case .notAuthenticated: return "Not signed in"
        case .authenticating:   return "Signing in"
        case .authenticated:    return "Signed in"
        case .tokenExpired:     return "Token expired"
        case .refreshing:       return "Refreshing"
        case .error(let msg):   return "Error: \(msg)"
        }
    }

    var loginFlowText: String {
        switch loginFlowState {
        case .idle:                 return "Idle"
        case .preparing:            return "Preparing"
        case .openingBrowser:       return "Open browser"
        case .waitingAuthorization: return "Waiting for authorization"
        case .exchangingToken:      return "Exchange token"
        case .success:              return "Success"
        case .error:                return "Failed"
        case .cancelled:            return "Cancelled"
        }
    }
}

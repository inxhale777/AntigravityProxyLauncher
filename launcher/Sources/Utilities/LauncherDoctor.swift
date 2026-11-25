import Foundation

struct LauncherDoctor {
    private let detection = AppDetectionService()
    private let verifier = PatchVerificationService()
    private let patch = PatchService()
    private let migration = MigrationService()
    private let launch = LaunchService()
    private let settingsService = AppSettingsService()

    func run() -> Int32 {
        print("=== Antigravity Proxy Launcher Doctor ===")
        print("Time: \(Date())")
        print("Target path: \(FileSystemPaths.targetApp.path)")
        print("Patched app path: \(FileSystemPaths.patchedApp.path)")

        guard let app = detection.detectInstalledTargetApp() else {
            let failure = LauncherFailure(code: .targetAppMissing, message: "Original app not detected")
            print("Error: \(failure.formatted)")
            print("Tip: make sure \(FileSystemPaths.targetApp.path) exists")
            return failure.codeValue
        }

        print("Status: original app detected")
        if app.bundleIdentifier.isEmpty {
            print("Bundle ID: N/A (CLI binary)")
        } else {
            print("Bundle ID: \(app.bundleIdentifier)")
        }
        print("Version: \(app.version)")
        if app.executableRelativePath.isEmpty {
            print("Executable: (CLI binary, no bundle)")
        } else {
            print("Executable: \(app.executableRelativePath)")
        }
        print("Architectures: \(app.architectures.joined(separator: ", "))")

        let dylibSource = FileSystemPaths.runtimeDylibCandidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if let dylibSource {
            print("Dylib resource: found (\(dylibSource.path))")
        } else {
            print("Dylib resource: missing")
            let failure = LauncherFailure(code: .runtimeAssetMissing, message: "libAntigravityTun.dylib is missing")
            print("Error: \(failure.formatted)")
            print("Tip: run legacy_scripts/compile_without_xcode.sh, or place it in launcher/Resources or legacy_scripts")
            return failure.codeValue
        }

        print("Doctor check finished: the GUI repair flow can continue.")
        return LauncherErrorCode.success.rawValue
    }


    func verifyPatchedAppFromCLI() -> Int32 {
        do {
            try verifier.verifyPatchedResult()
            print("Patched app verified")
            return LauncherErrorCode.success.rawValue
        } catch {
            let failure = LauncherErrorMapper.map(error)
            print("Patched app verification failed: \(failure.formatted)")
            return failure.codeValue
        }
    }

    func patchAndLaunchFromCLI() -> Int32 {
        print("=== Antigravity Proxy Launcher CLI Patch Workflow ===")

        let doctorCode = run()
        if doctorCode != 0 {
            print("Aborted: doctor check failed.")
            return doctorCode
        }

        do {
            print("[1/4] Migrate data")
            try migration.migrateSandboxData()

            print("[2/4] Apply patch")
            try patch.preparePatchedBundle(onProgress: { message in
                print("  - \(message)")
            })

            print("[3/4] Verify patch")
            try verifier.verifyPatchedResult()

            print("[4/4] Launch patched app")
            let _ = try runAsyncBlocking {
                let settings = try? settingsService.load()
                try await launch.launchPatchedApp(settings: settings)
            }

            print("CLI run completed successfully")
            return LauncherErrorCode.success.rawValue
        } catch {
            let failure = LauncherErrorMapper.map(error)
            print("CLI run failed: \(failure.formatted)")
            return failure.codeValue
        }
    }

    private func runAsyncBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<T, Error>?

        Task {
            do {
                outcome = .success(try await operation())
            } catch {
                outcome = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try outcome!.get()
    }
}

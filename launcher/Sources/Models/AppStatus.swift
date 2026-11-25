import Foundation

enum AppStatus: Equatable {
    case targetAppMissing
    case targetAppUnsupportedVersion(String)
    case targetAppInstalled
    case patchedAppMissing
    case patchedAppOutdated
    case patching
    case cleaning
    case patchedReady
    case launching
    case running
    case repairRequired(String)
    case error(String)

    var title: String {
        let appName = FileSystemPaths.activeApp.displayName
        let isCLI = FileSystemPaths.activeApp.targetType == .cliBinary
        switch self {
        case .targetAppMissing:
            return "\(appName) not detected"
        case .targetAppUnsupportedVersion:
            return "Unsupported version"
        case .targetAppInstalled:
            return "\(appName) installed"
        case .patchedAppMissing:
            return "Patched app not found"
        case .patchedAppOutdated:
            return "Patched app out of date"
        case .patching:
            return "Repairing"
        case .cleaning:
            return "Cleaning environment"
        case .patchedReady:
            return "Repair complete"
        case .launching:
            return isCLI ? "Verifying" : "Launching"
        case .running:
            return isCLI ? "\(appName) available" : "Running"
        case .repairRequired:
            return "Repair needed"
        case .error:
            return "Error"
        }
    }

    var description: String {
        let appName = FileSystemPaths.activeApp.displayName
        let exeName = FileSystemPaths.activeApp.executableName
        let isCLI = FileSystemPaths.activeApp.targetType == .cliBinary
        switch self {
        case .targetAppMissing:
            return "Install \(appName) first: \(FileSystemPaths.targetApp.path)"
        case .targetAppUnsupportedVersion(let version):
            return "Version \(version) is not in the compatibility list."
        case .targetAppInstalled:
            return "The repair flow can run."
        case .patchedAppMissing:
            return "The patched app has not been created yet."
        case .patchedAppOutdated:
            return "The original app has been updated. Repair again."
        case .patching:
            return "Copying and injecting resources and writing metadata."
        case .cleaning:
            return "Removing the patched app and related configuration."
        case .patchedReady:
            return isCLI ? "Repair complete. The \(exeName) command is available in a terminal." : "The patched app can be launched."
        case .launching:
            return isCLI ? "Running \(exeName) --version to verify the installation..." : "Starting the patched app."
        case .running:
            return isCLI ? "Proxy injection is ready: running \(exeName) in a terminal goes through the proxy automatically." : "Patched app is running."
        case .repairRequired(let reason):
            return reason
        case .error(let message):
            return message
        }
    }
}

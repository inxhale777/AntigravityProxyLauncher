import Foundation

enum LauncherCLICommand: Equatable {
    case doctor
    case verifyPatched
    case patchAndLaunch
    case help
    case unknown(String)
    case none
}

enum LauncherCLICommandParser {
    static func parse(from args: [String]) -> LauncherCLICommand {
        let cliArgs = Array(args.dropFirst())

        for arg in cliArgs {
            if arg == "--" {
                continue
            }

            switch arg {
            case "--doctor": return .doctor
            case "--verify-patched": return .verifyPatched
            case "--patch-and-launch": return .patchAndLaunch
            case "--help", "-h": return .help
            default:
                if arg.hasPrefix("--") || arg == "-h" {
                    return .unknown(arg)
                }
            }
        }

        return .none
    }

    static var helpText: String {
        let executableName = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "AntigravityProxyLauncher"

        return """
Usage:
    \(executableName) --doctor
    \(executableName) --export-diagnostics
    \(executableName) --verify-patched
    \(executableName) --patch-and-launch
    \(executableName) --help

Legacy SwiftPM mode:
    # Do not start non-.app builds without arguments (no .app bundle metadata)
  swift run AntigravityProxyLauncher -- --doctor
  swift run AntigravityProxyLauncher -- --export-diagnostics
  swift run AntigravityProxyLauncher -- --verify-patched
  swift run AntigravityProxyLauncher -- --patch-and-launch
  swift run AntigravityProxyLauncher -- --help

GUI mode (.app):
    open /path/to/AntigravityProxyLauncher.app
"""
    }
}
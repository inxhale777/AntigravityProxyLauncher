import Foundation

enum LaunchWorkflowStep: String, CaseIterable, Identifiable {
    case detect = "Detect target app"
    case migration = "Migrate existing data"
    case patch = "Repair app bundle"
    case verify = "Verify repair result"
    case launch = "Launch patched app"

    var id: String { rawValue }
}

enum LaunchWorkflowStepState {
    case pending
    case running
    case completed
    case failed
}

struct LaunchWorkflowItem: Identifiable {
    let id: LaunchWorkflowStep
    var state: LaunchWorkflowStepState
    var detail: String?

    var title: String {
        id.rawValue
    }
}

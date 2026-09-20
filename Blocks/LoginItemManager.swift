import Foundation
import ServiceManagement
import Combine

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var errorMessage: String?

    func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
        print("[Login] Status: \(status)")
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("[Login] Registered as login item")
            } else {
                try SMAppService.mainApp.unregister()
                print("[Login] Unregistered as login item")
            }
            errorMessage = nil
        } catch {
            print("[Login] Failed to \(enabled ? "register" : "unregister"): \(error.localizedDescription)")
            errorMessage = "Couldn't \(enabled ? "enable" : "disable") launch at login."
        }
        // Always re-derive from the real system status, whether this
        // succeeded or not, so the toggle never shows a state that isn't
        // actually true.
        refreshStatus()
    }
}

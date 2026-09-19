import Carbon.HIToolbox
import Foundation

/// Registers a single global hotkey (Command-Shift-A) using macOS's Carbon
/// Hot Key API. This is the same OS-arbitrated mechanism most third-party
/// hotkey utilities use: if the combination is already taken by something
/// else, registration fails with an error instead of silently doing
/// nothing or falling back to a different combination.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onTrigger: () -> Void

    private static let signature: OSType = 0x424C4B53 // 'BLKS'
    private static let hotKeyID = EventHotKeyID(signature: signature, id: 1)

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    /// Returns nil on success, or a user-facing message describing why
    /// Command-Shift-A couldn't be registered.
    @discardableResult
    func register() -> String? {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onTrigger() }
            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            let message = "Couldn't set up the quick-add hotkey listener (error \(handlerStatus))."
            print("[Hotkey] \(message)")
            return message
        }

        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_A)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, Self.hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            let message = "Command-Shift-A is already in use by another app, so Blocks couldn't register its quick-add hotkey (error \(registerStatus)). Free up that combination, then relaunch Blocks."
            print("[Hotkey] Registration failed: OSStatus \(registerStatus)")
            return message
        }

        print("[Hotkey] Registered Command-Shift-A for quick add")
        return nil
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

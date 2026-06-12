import AppKit
import Carbon.HIToolbox

/// Fixed global hotkey ⌃⌥⌘L via Carbon RegisterEventHotKey — no accessibility
/// permission needed, unlike CGEventTap.
@MainActor
public final class HotkeyManager {
    /// The hotkey, in one place: ⌃⌥⌘ + L.
    private static let kHotkeyKeyCode = UInt32(kVK_ANSI_L)
    private static let kHotkeyModifiers = UInt32(controlKey | optionKey | cmdKey)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onPress: () -> Void

    public init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Returns false when registration fails (combo taken) — caller logs and
    /// continues; the menu bar icon still works.
    @discardableResult
    public func register() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetEventDispatcherTarget(), hotkeyEventCallback, 1,
                                  &eventType, selfPointer, &eventHandlerRef) == noErr else {
            return false
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_534E) /* "CLSN" */, id: 1)
        let status = RegisterEventHotKey(Self.kHotkeyKeyCode, Self.kHotkeyModifiers,
                                         hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    fileprivate func fire() {
        onPress()
    }
}

private func hotkeyEventCallback(_ handler: EventHandlerCallRef?,
                                 _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    // Carbon dispatches hotkey events on the main thread.
    MainActor.assumeIsolated { manager.fire() }
    return noErr
}

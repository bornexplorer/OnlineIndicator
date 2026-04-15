import AppKit
import Carbon
import CoreWLAN

// MARK: - Shortcut Model

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt   // NSEvent.ModifierFlags rawValue

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Human-readable representation, e.g. "⌘⇧W"
    var displayString: String {
        var s = ""
        let flags = modifierFlags
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += KeyboardShortcut.keyCodeToString(keyCode)
        return s
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 36:  return "↩"
        case 48:  return "⇥"
        case 49:  return "Space"
        case 51:  return "⌫"
        case 53:  return "Esc"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 99:  return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 115: return "Home"
        case 116: return "PgUp"
        case 117: return "⌦"
        case 119: return "End"
        case 121: return "PgDn"
        case 122: return "F1"
        case 120: return "F2"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:  break
        }
        let src = TISCopyCurrentKeyboardInputSource().takeUnretainedValue()
        if let dataRef = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) {
            let layoutData = unsafeBitCast(dataRef, to: CFData.self)
            let keyLayout  = unsafeBitCast(CFDataGetBytePtr(layoutData),
                                           to: UnsafePointer<UCKeyboardLayout>.self)
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            UCKeyTranslate(keyLayout, keyCode, UInt16(kUCKeyActionDisplay),
                           0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit),
                           &deadKeyState, 4, &length, &chars)
            if length > 0 {
                return String(String.UnicodeScalarView(
                    chars[0..<length].compactMap { Unicode.Scalar($0) }
                )).uppercased()
            }
        }
        return "(\(keyCode))"
    }

    // MARK: - Carbon conversion helpers

    /// Converts NSEvent modifier flags to Carbon modifier flags for RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { carbon |= UInt32(cmdKey)   }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey)}
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey)  }
        return carbon
    }
}

// MARK: - Carbon Hot Key Handler
//
// RegisterEventHotKey works system-wide WITHOUT requiring Accessibility permission.
// It is the same mechanism used by system-level shortcuts (e.g. ⌘Space for Spotlight).

private var gHotKeyActions: [UInt32: () -> Void] = [:]
private var gNextHotKeyID: UInt32 = 1

private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hkID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    if let action = gHotKeyActions[hkID.id] {
        DispatchQueue.main.async { action() }
    }
    return noErr
}

// MARK: - Manager

final class KeyboardShortcutManager {

    static let shared = KeyboardShortcutManager()

    // UserDefaults keys
    static let wifiToggleKey   = "shortcut.wifiToggle"
    static let wifiSettingsKey = "shortcut.wifiSettings"
    static let vpnSettingsKey  = "shortcut.vpnSettings"

    /// Set by AppDelegate so that each shortcut shows a popover before executing.
    /// When nil, actions fall back to direct execution.
    var shortcutActionHandler: ((String) -> Void)?

    // Carbon state
    private var hotKeyRefs: [String: EventHotKeyRef?] = [:]
    private var hotKeyIDs:  [String: UInt32]          = [:]
    private var eventHandler: EventHandlerRef?

    /// Call once from AppDelegate after the status item is set up.
    func start() {
        installCarbonHandler()
        reloadAll()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange),
            name: .keyboardShortcutsChanged,
            object: nil
        )
    }

    // MARK: - Persistence

    func shortcut(for key: String) -> KeyboardShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let sc   = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        else { return nil }
        return sc
    }

    func save(_ shortcut: KeyboardShortcut?, for key: String) {
        if let sc = shortcut, let data = try? JSONEncoder().encode(sc) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .keyboardShortcutsChanged, object: nil)
    }

    /// Temporarily unregisters all Carbon hot keys (e.g. while a shortcut recorder is active).
    func suspend() { unregisterAll() }

    /// Re-registers all saved Carbon hot keys after a suspend.
    func resume()  { reloadAll() }

    // MARK: - Private

    private func installCarbonHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(),
                            carbonHotKeyHandler,
                            1, &eventType, nil, &eventHandler)
    }

    @objc private func shortcutsDidChange() {
        reloadAll()
    }

    private func reloadAll() {
        unregisterAll()

        register(key: Self.wifiToggleKey) { [weak self] in
            if let handler = self?.shortcutActionHandler {
                handler(Self.wifiToggleKey)
            } else {
                guard let iface = CWWiFiClient.shared().interface() else { return }
                let turningOn = !iface.powerOn()
                try? iface.setPower(turningOn)
            }
        }

        register(key: Self.wifiSettingsKey) { [weak self] in
            if let handler = self?.shortcutActionHandler {
                handler(Self.wifiSettingsKey)
            } else {
                if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        register(key: Self.vpnSettingsKey) { [weak self] in
            if let handler = self?.shortcutActionHandler {
                handler(Self.vpnSettingsKey)
            } else {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func register(key: String, action: @escaping () -> Void) {
        guard let sc = shortcut(for: key) else { return }

        let uid = gNextHotKeyID
        gNextHotKeyID += 1

        let hkID  = EventHotKeyID(signature: OSType(0x4F49_484B), id: uid) // 'OIHK'
        var hkRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(sc.keyCode),
            sc.carbonModifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &hkRef
        )

        guard status == noErr else { return }

        hotKeyRefs[key] = hkRef
        hotKeyIDs[key]  = uid
        gHotKeyActions[uid] = action
    }

    private func unregisterAll() {
        for (key, ref) in hotKeyRefs {
            if let r = ref { UnregisterEventHotKey(r) }
            if let uid = hotKeyIDs[key] { gHotKeyActions.removeValue(forKey: uid) }
        }
        hotKeyRefs.removeAll()
        hotKeyIDs.removeAll()
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let keyboardShortcutsChanged = Notification.Name("keyboardShortcutsChanged")
}

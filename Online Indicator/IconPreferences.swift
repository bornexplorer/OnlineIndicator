import AppKit

struct IconPreferences {

    // MARK: - Slot

    struct Slot {
        var symbolName: String
        var color: NSColor
        var menuLabel: String
        var menuLabelEnabled: Bool

        static let defaultConnected = Slot(symbolName: "wifi", color: .systemGreen,  menuLabel: "", menuLabelEnabled: false)
        static let defaultBlocked   = Slot(symbolName: "wifi", color: .systemYellow, menuLabel: "", menuLabelEnabled: false)
        static let defaultNoNetwork = Slot(symbolName: "wifi.slash",       color: .systemRed,    menuLabel: "", menuLabelEnabled: false)
    }

    // MARK: - Read

    static func slot(for status: AppState.ConnectionStatus) -> Slot {
        switch status {
        case .connected: return load(key: "connected",  fallback: .defaultConnected)
        case .blocked:   return load(key: "blocked",    fallback: .defaultBlocked)
        case .noNetwork: return load(key: "noNetwork",  fallback: .defaultNoNetwork)
        }
    }

    static func defaultSlot(for status: AppState.ConnectionStatus) -> Slot {
        switch status {
        case .connected: return .defaultConnected
        case .blocked:   return .defaultBlocked
        case .noNetwork: return .defaultNoNetwork
        }
    }

    // MARK: - Write

    static func save(_ slot: Slot, for status: AppState.ConnectionStatus) {
        let key = storageKey(for: status)
        UserDefaults.standard.set(slot.symbolName,       forKey: "iconSymbol.\(key)")
        UserDefaults.standard.set(slot.menuLabel,        forKey: "iconLabel.\(key)")
        UserDefaults.standard.set(slot.menuLabelEnabled, forKey: "iconLabelEnabled.\(key)")
        saveColor(slot.color, forKey: "iconColor.\(key)")

        NotificationCenter.default.post(name: .iconPreferencesChanged, object: nil)
    }

    // MARK: - Reset

    static func resetAll() {
        for status in [AppState.ConnectionStatus.connected, .blocked, .noNetwork] {
            let key = storageKey(for: status)
            UserDefaults.standard.removeObject(forKey: "iconSymbol.\(key)")
            UserDefaults.standard.removeObject(forKey: "iconColor.\(key)")
            UserDefaults.standard.removeObject(forKey: "iconLabel.\(key)")
            UserDefaults.standard.removeObject(forKey: "iconLabelEnabled.\(key)")
        }
        NotificationCenter.default.post(name: .iconPreferencesChanged, object: nil)
    }

    // MARK: - Helpers

    private static func storageKey(for status: AppState.ConnectionStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .blocked:   return "blocked"
        case .noNetwork: return "noNetwork"
        }
    }

    private static func load(key: String, fallback: Slot) -> Slot {
        let symbol  = UserDefaults.standard.string(forKey: "iconSymbol.\(key)") ?? fallback.symbolName
        let label   = UserDefaults.standard.string(forKey: "iconLabel.\(key)")  ?? fallback.menuLabel
        let color   = loadColor(forKey: "iconColor.\(key)") ?? fallback.color

        let enabled = UserDefaults.standard.object(forKey: "iconLabelEnabled.\(key)") != nil
                      ? UserDefaults.standard.bool(forKey: "iconLabelEnabled.\(key)")
                      : fallback.menuLabelEnabled
        return Slot(symbolName: symbol, color: color, menuLabel: label, menuLabelEnabled: enabled)
    }

    private static func saveColor(_ color: NSColor, forKey key: String) {
        let c = color.usingColorSpace(.sRGB) ?? color
        UserDefaults.standard.set(
            [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent],
            forKey: key
        )
    }

    private static func loadColor(forKey key: String) -> NSColor? {
        guard let arr = UserDefaults.standard.array(forKey: key) as? [Double],
              arr.count == 4 else { return nil }
        return NSColor(srgbRed: arr[0], green: arr[1], blue: arr[2], alpha: arr[3])
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let iconPreferencesChanged     = Notification.Name("iconPreferencesChanged")
    static let settingsWindowDidBecomeKey = Notification.Name("settingsWindowDidBecomeKey")
    static let locationAuthorizationChanged = Notification.Name("locationAuthorizationChanged")
}

import SwiftUI
import AppKit
import CoreWLAN
import CoreLocation

@main
struct OnlineIndicatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem!
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private var wifiToggleView:       MenuWiFiToggleView?
    private var networkSectionHeader: NSMenuItem?
    private var wifiNameMenuItem:     NSMenuItem?
    private var ipv4MenuItem:         NSMenuItem?
    private var ipv6MenuItem:         NSMenuItem?
    private var mainMenu:             NSMenu?

    private var currentStatus: AppState.ConnectionStatus = .noNetwork
    private var lastIPv4: String?
    private var lastIPv6: String?

    private var hasInitialized        = false
    private var lastWiFiPowerChangeDate: Date?
    private var lastKnownSSID: String?
    private var appInitiatedWiFiToggle  = false
    private var popoverManager: PopoverManager!
    private var pendingWifiNameInMenuEnable = false
    private var wifiPowerDebounce: Timer?
    private var ssidDebounce:      Timer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = SSIDManager.shared   // ensure CLLocationManager is created on the main thread

        UserDefaults.standard.register(defaults: [
            "leftRightClickEnabled": true,
            "leftClickAction":       "wifi",
            "rightClickAction":      "menu",
            "leftRightClickSwapped": false,
            "hideIPv4":              false,
            "hideIPv6":              false,
            "useSSIDAsMenuBarLabel": false,
            "showWifiNameInMenu":    false
        ])

        if UserDefaults.standard.object(forKey: "refreshInterval") == nil {
            showOnboarding()
        } else {
            startApp()
        }
    }

    private func startApp() {
        setupStatusItem()

        // Seed lastKnownSSID immediately if location is already authorized;
        // otherwise fall back to the airport tool which may still work on some systems.
        if let ssid = SSIDManager.shared.currentSSID() {
            lastKnownSSID = ssid
        } else {
            fetchSSIDFromAirport { [weak self] ssid in
                self?.lastKnownSSID = ssid
            }
        }

        // When location auth changes, refresh the SSID and update icon/menu if needed.
        // If auth is revoked, fall back to the airport CLI so the name stays visible.
        SSIDManager.shared.onAuthorizationChange = { [weak self] authorized in
            guard let self else { return }
            if authorized {
                self.lastKnownSSID = SSIDManager.shared.currentSSID() ?? self.lastKnownSSID
                // If the user just granted permission via the menu "Enable Wi-Fi Name" action,
                // commit the showWifiNameInMenu preference now.
                if self.pendingWifiNameInMenuEnable {
                    self.pendingWifiNameInMenuEnable = false
                    UserDefaults.standard.set(true, forKey: "showWifiNameInMenu")
                }
            } else {
                // Location turned off — airport can still read SSID on many macOS versions
                self.fetchSSIDFromAirport { [weak self] ssid in
                    guard let self else { return }
                    if let ssid { self.lastKnownSSID = ssid }
                }
            }
            if UserDefaults.standard.bool(forKey: "useSSIDAsMenuBarLabel") {
                self.updateIcon(for: self.currentStatus)
            }
        }

        AppState.shared.statusUpdateHandler = { [weak self] status in
            guard let self else { return }

            let previous = self.currentStatus
            self.currentStatus = status
            self.updateIcon(for: status)

            if UserDefaults.standard.bool(forKey: "useSSIDAsMenuBarLabel"),
               status == .connected || status == .blocked {
                if let ssid = SSIDManager.shared.currentSSID() {
                    if ssid != self.lastKnownSSID {
                        self.lastKnownSSID = ssid
                        self.updateIcon(for: self.currentStatus)
                    }
                } else {
                    self.fetchSSIDFromAirport { [weak self] ssid in
                        guard let self else { return }
                        if let ssid, ssid != self.lastKnownSSID {
                            self.lastKnownSSID = ssid
                            self.updateIcon(for: self.currentStatus)
                        }
                    }
                }
            }

            guard self.hasInitialized else { self.hasInitialized = true; return }

            // Suppress duplicate notifications triggered by Wi-Fi power events.
            if let pwDate = self.lastWiFiPowerChangeDate,
               Date().timeIntervalSince(pwDate) < 3.5 { return }

            guard status != previous else { return }

            self.popoverManager.showConnectionStatus(status)
        }

        AppState.shared.checkNowResultHandler = { [weak self] status in
            guard let self else { return }
            self.popoverManager.showConnectionStatus(status)
        }

        AppState.shared.start()

        if wifiInterface != nil {
            CWWiFiClient.shared().delegate = self
            try? CWWiFiClient.shared().startMonitoringEvent(with: .powerDidChange)
            try? CWWiFiClient.shared().startMonitoringEvent(with: .ssidDidChange)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.popoverManager.showLaunchTooltip()
        }

        NotificationCenter.default.addObserver(
            forName: .iconPreferencesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if UserDefaults.standard.bool(forKey: "useSSIDAsMenuBarLabel") {
                let ssid = SSIDManager.shared.currentSSID()
                if let ssid {
                    self.lastKnownSSID = ssid
                    self.updateIcon(for: self.currentStatus)
                } else {
                    self.fetchSSIDFromAirport { [weak self] ssid in
                        guard let self else { return }
                        if let ssid { self.lastKnownSSID = ssid }
                        self.updateIcon(for: self.currentStatus)
                    }
                }
            } else {
                self.updateIcon(for: self.currentStatus)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow { settingsWindow = nil }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        updateWiFiToggleView()

        let addresses = IPAddressProvider.current()
        lastIPv4 = addresses.ipv4
        lastIPv6 = addresses.ipv6

        let hideIPv4 = UserDefaults.standard.bool(forKey: "hideIPv4")
        let hideIPv6 = UserDefaults.standard.bool(forKey: "hideIPv6")
        let showWifiName = UserDefaults.standard.bool(forKey: "showWifiNameInMenu")

        // Wi-Fi name row — always shown.
        // Feature ON + ssid found  → white label value, non-interactive.
        // Feature ON + ssid nil    → "Requires Location Access" in accent, tappable (same action as Enable).
        // Feature OFF              → "Enable Wi-Fi Name" in accent, tappable.
        networkSectionHeader?.isHidden = false
        if showWifiName {
            let ssid = SSIDManager.shared.currentSSID() ?? lastKnownSSID
            if let ssid {
                // Keep isEnabled = true with a no-op action so AppKit does NOT
                // dim the attributed title. action = nil forces dimming regardless
                // of isEnabled, which is why the text wasn't appearing white.
                wifiNameMenuItem?.action    = #selector(wifiNameDisplayTapped)
                wifiNameMenuItem?.target    = self
                wifiNameMenuItem?.isEnabled = true
                wifiNameMenuItem?.attributedTitle = wifiNameAttributedString(ssid: ssid)
            } else {
                wifiNameMenuItem?.action    = #selector(enableWifiNameFromMenu)
                wifiNameMenuItem?.target    = self
                wifiNameMenuItem?.isEnabled = true
                wifiNameMenuItem?.attributedTitle = wifiNameUnavailableAttributedString()
            }
        } else {
            wifiNameMenuItem?.action    = #selector(enableWifiNameFromMenu)
            wifiNameMenuItem?.target    = self
            wifiNameMenuItem?.isEnabled = true
            wifiNameMenuItem?.attributedTitle = enableWifiNameAttributedString()
        }

        ipv4MenuItem?.isHidden = hideIPv4
        ipv6MenuItem?.isHidden = hideIPv6

        if !hideIPv4 {
            ipv4MenuItem?.attributedTitle = ipAttributedString(
                label: "IPv4", value: addresses.ipv4 ?? "Unavailable", available: addresses.ipv4 != nil)
        }
        if !hideIPv6 {
            ipv6MenuItem?.attributedTitle = ipAttributedString(
                label: "IPv6", value: addresses.ipv6 ?? "Unavailable", available: addresses.ipv6 != nil)
        }
    }

    // MARK: - Menu Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popoverManager = PopoverManager { [weak self] in self?.statusItem.button }
        updateIcon(for: .noNetwork)

        let menu = NSMenu()
        menu.delegate = self
        menu.minimumWidth = 280

        let toggleView = MenuWiFiToggleView(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        toggleView.toggleAction = { [weak self] in self?.performWiFiToggleFromMenu() }
        wifiToggleView = toggleView
        let toggleItem = NSMenuItem()
        toggleItem.view = toggleView
        menu.addItem(toggleItem)

        let wifiSettingsItem = NSMenuItem(title: "Wi-Fi Settings…",
                                          action: #selector(openWiFiSettingsFromMenu), keyEquivalent: "")
        wifiSettingsItem.target = self
        menu.addItem(wifiSettingsItem)

        menu.addItem(.separator())

        let networkHeader = sectionHeaderItem(title: "Network")
        networkSectionHeader = networkHeader
        menu.addItem(networkHeader)

        let wifiNameItem = NSMenuItem(title: "", action: #selector(enableWifiNameFromMenu), keyEquivalent: "")
        wifiNameItem.target = self
        wifiNameItem.isEnabled = true
        wifiNameMenuItem = wifiNameItem
        menu.addItem(wifiNameItem)

        let ipv4Item = NSMenuItem(title: "", action: #selector(copyIPv4), keyEquivalent: "")
        ipv4Item.target = self
        ipv4Item.toolTip = "Click to copy"
        ipv4Item.attributedTitle = ipAttributedString(label: "IPv4", value: "Loading…", available: false)
        ipv4MenuItem = ipv4Item
        menu.addItem(ipv4Item)

        let ipv6Item = NSMenuItem(title: "", action: #selector(copyIPv6), keyEquivalent: "")
        ipv6Item.target = self
        ipv6Item.toolTip = "Click to copy"
        ipv6Item.attributedTitle = ipAttributedString(label: "IPv6", value: "Loading…", available: false)
        ipv6MenuItem = ipv6Item
        menu.addItem(ipv6Item)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings",
                                      action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        menu.addItem(.separator())

        let infoRow = MenuAppInfoView(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let infoItem = NSMenuItem()
        infoItem.view      = infoRow
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        mainMenu = menu

        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Section header helper

    private func sectionHeaderItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        return item
    }

    // MARK: - Wi-Fi helpers

    private var wifiInterface: CWInterface? { CWWiFiClient.shared().interface() }

    private func fetchSSIDFromAirport(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let airportPath = "/System/Library/PrivateFrameworks/Apple80211.framework" +
                              "/Versions/Current/Resources/airport"
            guard FileManager.default.isExecutableFile(atPath: airportPath) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: airportPath)
            process.arguments     = ["-I"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            var parsed: String?
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("SSID: ") {
                    let value = String(trimmed.dropFirst("SSID: ".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { parsed = value }
                    break
                }
            }
            DispatchQueue.main.async { completion(parsed) }
        }
    }

    private func updateWiFiToggleView() {
        if let iface = wifiInterface {
            wifiToggleView?.setState(isOn: iface.powerOn(), isAvailable: true)
        } else {
            wifiToggleView?.setState(isOn: false, isAvailable: false)
        }
    }

    private func performWiFiToggleFromMenu() {
        mainMenu?.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.performWiFiToggle()
        }
    }

    private func performWiFiToggle() {
        guard let iface = wifiInterface else { return }
        let turningOn = !iface.powerOn()
        appInitiatedWiFiToggle = true
        popoverManager.showWiFiToggling(turningOn: turningOn)
        do { try iface.setPower(turningOn) }
        catch {
            appInitiatedWiFiToggle = false
            popoverManager.dismiss()
        }
    }

    @objc private func openWiFiSettingsFromMenu() {
        popoverManager.showOpeningWiFiSettings()
        openWiFiSettings()
    }

    // MARK: - Click Handling

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }

        let enabled  = UserDefaults.standard.bool(forKey: "leftRightClickEnabled")
        let swapped  = UserDefaults.standard.bool(forKey: "leftRightClickSwapped")
        let leftAct  = UserDefaults.standard.string(forKey: "leftClickAction")  ?? "wifi"
        let rightAct = UserDefaults.standard.string(forKey: "rightClickAction") ?? "menu"

        guard enabled else { showDropdownMenu(); return }

        let isLeft = event.type == .leftMouseUp
        let action = swapped
            ? (isLeft ? rightAct : leftAct)
            : (isLeft ? leftAct  : rightAct)

        performAction(action)
    }

    private func performAction(_ action: String) {
        switch action {
        case "wifi":
            popoverManager.showOpeningWiFiSettings()
            openWiFiSettings()
        case "checkNow":
            popoverManager.showChecking()
            AppState.shared.checkNow()
        case "wifiToggle":
            performWiFiToggle()
        case "settings":
            openSettings()
        default:
            showDropdownMenu()
        }
    }

    private func showDropdownMenu() {
        statusItem.menu = mainMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - IP attributed string

    private func ipAttributedString(label: String, value: String, available: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: label, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        result.append(NSAttributedString(string: "   ", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]))
        result.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: available ? NSColor.labelColor : NSColor.tertiaryLabelColor
        ]))
        return result
    }

    // Wi-Fi name shown when the feature is enabled — value colour and weight match IPv4/IPv6.
    // "Wi-Fi  " is 7 monospaced chars, same width as "IPv4   " / "IPv6   ", so values start at the same x.
    private func wifiNameAttributedString(ssid: String) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "Wi-Fi  ", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        s.append(NSAttributedString(string: ssid, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]))
        return s
    }

    // Shown when showWifiNameInMenu is ON but no SSID is available (location not granted,
    // or Wi-Fi off). Styled as the label column + tappable accent-colour value so the user
    // knows they can click it to grant access or troubleshoot.
    private func wifiNameUnavailableAttributedString() -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "Wi-Fi  ", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        s.append(NSAttributedString(string: "Requires Location Access", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.controlAccentColor
        ]))
        return s
    }

    // Shown when the feature is disabled — accent-coloured, acts as a prompt to enable.
    private func enableWifiNameAttributedString() -> NSAttributedString {
        NSAttributedString(string: "Enable Wi-Fi Name", attributes: [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: NSColor.controlAccentColor
        ])
    }

    // No-op target for the Wi-Fi name display row when an SSID is shown.
    // An NSMenuItem with action = nil is dimmed by AppKit regardless of isEnabled;
    // assigning any selector keeps the item at full brightness without any click behavior.
    @objc private func wifiNameDisplayTapped() {}

    // Called when the user clicks "Enable Wi-Fi Name" in the menu.
    @objc private func enableWifiNameFromMenu() {
        mainMenu?.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            switch SSIDManager.shared.authorizationStatus {
            case .authorizedAlways:
                UserDefaults.standard.set(true, forKey: "showWifiNameInMenu")
                self.lastKnownSSID = SSIDManager.shared.currentSSID() ?? self.lastKnownSSID
            case .notDetermined:
                let alert = NSAlert()
                alert.messageText     = "Location Access Needed"
                alert.informativeText = "To read your Wi-Fi network name, \(AppInfo.appName) needs Location Services access. Your location is never stored or shared — macOS requires it solely to identify which network you're connected to."
                alert.addButton(withTitle: "Allow Access")
                alert.addButton(withTitle: "Not Now")
                alert.alertStyle = .informational
                if alert.runModal() == .alertFirstButtonReturn {
                    self.pendingWifiNameInMenuEnable = true
                    SSIDManager.shared.requestAuthorization()
                }
            default:
                let alert = NSAlert()
                alert.messageText     = "Location Services Disabled"
                alert.informativeText = "Location Services are currently disabled. Enable them in System Settings → Privacy & Security → Location Services to show your Wi-Fi name."
                alert.addButton(withTitle: "Open Privacy Settings")
                alert.addButton(withTitle: "Not Now")
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Copy actions

    @objc private func copyIPv4() {
        guard let ip = lastIPv4 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        popoverManager.showCopied("IPv4 Copied")
    }

    @objc private func copyIPv6() {
        guard let ip = lastIPv6 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        popoverManager.showCopied("IPv6 Copied")
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.startApp()
            self?.onboardingWindow = nil
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Icon

    private func updateIcon(for status: AppState.ConnectionStatus) {
        guard let button = statusItem.button else { return }

        let pref = IconPreferences.slot(for: status)

        let symbolName: String
        let color: NSColor

        if NSImage(systemSymbolName: pref.symbolName, accessibilityDescription: nil) != nil {
            symbolName = pref.symbolName
            color = pref.color
        } else {
            switch status {
            case .connected: symbolName = "wifi";       color = .systemGreen
            case .blocked:   symbolName = "wifi";       color = .systemYellow
            case .noNetwork: symbolName = "wifi.slash"; color = .systemRed
            }
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }

        let tinted = baseImage.copy() as! NSImage
        tinted.lockFocus()
        color.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let useSSIDLabel = UserDefaults.standard.bool(forKey: "useSSIDAsMenuBarLabel")
        var rawLabel  = String(pref.menuLabel.prefix(15)).trimmingCharacters(in: .whitespaces)
        var showLabel = pref.menuLabelEnabled && !rawLabel.isEmpty

        if useSSIDLabel && (status == .connected || status == .blocked) {
            let ssid = SSIDManager.shared.currentSSID() ?? lastKnownSSID ?? ""
            if !ssid.isEmpty {
                rawLabel  = String(ssid.prefix(15))
                showLabel = true
            }
        }

        let barHeight = NSStatusBar.system.thickness
        let iconSize  = tinted.size

        if showLabel {
            let font = NSFont.menuBarFont(ofSize: 12)
            let attachment = NSTextAttachment()
            attachment.image = tinted
            attachment.bounds = NSRect(
                x: 0, y: (font.capHeight - iconSize.height) / 2,
                width: iconSize.width, height: iconSize.height
            )
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.labelColor, .baselineOffset: 0
            ]
            let full = NSMutableAttributedString()
            full.append(NSAttributedString(attachment: attachment))
            full.append(NSAttributedString(string: " " + rawLabel, attributes: textAttrs))
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = full
            return
        }

        let finalImage = NSImage(size: NSSize(width: barHeight, height: barHeight), flipped: false) { rect in
            let ox = (rect.width  - iconSize.width)  / 2
            let oy = (rect.height - iconSize.height) / 2
            tinted.draw(in: NSRect(x: ox, y: oy, width: iconSize.width, height: iconSize.height))
            return true
        }

        finalImage.isTemplate  = false
        button.image           = finalImage
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition   = .imageOnly
    }

    // MARK: - Settings

    @objc func openSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .settingsWindowDidBecomeKey, object: nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.center()
        window.title = AppInfo.appName
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - CWEventDelegate

extension AppDelegate: CWEventDelegate {

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.lastWiFiPowerChangeDate = Date()

            self.wifiPowerDebounce?.invalidate()
            self.wifiPowerDebounce = Timer.scheduledTimer(
                withTimeInterval: 0.3, repeats: false
            ) { [weak self] _ in
                guard let self, let iface = self.wifiInterface else { return }
                let isOn = iface.powerOn()

                if !isOn { self.lastKnownSSID = nil }

                if self.appInitiatedWiFiToggle {
                    self.appInitiatedWiFiToggle = false
                    self.popoverManager.dismiss()
                } else {
                    self.popoverManager.showWiFiPowerChanged(isOn: isOn)
                }

                self.updateWiFiToggleView()
            }
        }
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.ssidDebounce?.invalidate()

            self.ssidDebounce = Timer.scheduledTimer(
                withTimeInterval: 2.0, repeats: false
            ) { [weak self] _ in
                guard let self, let iface = self.wifiInterface else { return }

                self.fetchSSIDFromAirport { [weak self] airportSSID in
                    guard let self else { return }

                    let ssid = SSIDManager.shared.currentSSID() ?? airportSSID

                    if let ssid {
                        // Only show "Switched to" when the SSID actually changed to a different name.
                        if let previous = self.lastKnownSSID, previous != ssid {
                            self.popoverManager.showNetworkSwitched(to: ssid)
                        }
                        self.lastKnownSSID = ssid
                        self.updateIcon(for: self.currentStatus)
                        return
                    }

                    guard iface.powerOn() else { return }
                    guard self.lastKnownSSID != nil else { return }
                    if let pwDate = self.lastWiFiPowerChangeDate,
                       Date().timeIntervalSince(pwDate) < 4.0 { return }

                    self.lastKnownSSID = nil
                    self.popoverManager.showNoNetwork()
                }
            }
        }
    }
}

// MARK: - Wi-Fi Toggle Menu Row

private class MenuWiFiToggleView: NSView {

    var toggleAction: (() -> Void)?

    private var isOn        = false
    private var isAvailable = true

    private let pillW: CGFloat = 38
    private let pillH: CGFloat = 22
    private let rpad:  CGFloat = 17

    func setState(isOn: Bool, isAvailable: Bool) {
        self.isOn        = isOn
        self.isAvailable = isAvailable
        needsDisplay = true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width]
        updateTrackingAreas()
    }
    required init?(coder: NSCoder) { fatalError() }

    private var pillRect: NSRect {
        let pillX = bounds.width - rpad - pillW
        let pillY = (bounds.height - pillH) / 2
        return NSRect(x: pillX, y: pillY, width: pillW, height: pillH)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let lpad:     CGFloat = 17
        let iconSize: CGFloat = 13

        let iconColor  = isAvailable ? NSColor.labelColor : NSColor.disabledControlTextColor
        let iconSymbol = isOn ? "wifi" : "wifi.slash"
        if let iconImage = NSImage(systemSymbolName: iconSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)) {
            let tinted = iconImage.copy() as! NSImage
            tinted.lockFocus()
            iconColor.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let iconY = (bounds.height - tinted.size.height) / 2
            tinted.draw(in: NSRect(x: lpad, y: iconY, width: tinted.size.width, height: tinted.size.height))
        }

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: isAvailable ? NSColor.labelColor : NSColor.disabledControlTextColor
        ]
        let titleStr  = NSAttributedString(string: "Wi-Fi", attributes: titleAttrs)
        let titleSize = titleStr.size()
        let titleY    = (bounds.height - titleSize.height) / 2
        titleStr.draw(at: NSPoint(x: lpad + iconSize + 6, y: titleY))

        let pr = pillRect
        let pillColor: NSColor
        if !isAvailable {
            pillColor = NSColor(white: 0.5, alpha: 0.4)
        } else if isOn {
            pillColor = NSColor.controlAccentColor
        } else {
            pillColor = NSColor(white: 0.48, alpha: 1.0)
        }
        pillColor.setFill()
        NSBezierPath(roundedRect: pr, xRadius: pillH / 2, yRadius: pillH / 2).fill()

        let knobD: CGFloat = pillH - 4
        let knobX = isOn ? pr.minX + pillW - knobD - 2 : pr.minX + 2
        let knobY = pr.minY + 2
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: knobY, width: knobD, height: knobD)).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: pillRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        ))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        pillRect.contains(point) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        guard isAvailable, pillRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        toggleAction?()
    }
}

// MARK: - Menu App Info Row

private class MenuAppInfoView: NSView {

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let pad:  CGFloat = 14
        let midY: CGFloat = (bounds.height - 13) / 2

        let nameStr = NSAttributedString(string: AppInfo.appName, attributes: attrs)
        nameStr.draw(at: NSPoint(x: pad, y: midY))

        let versionStr = NSAttributedString(string: AppInfo.marketingVersion, attributes: attrs)
        let versionW = versionStr.size().width
        versionStr.draw(at: NSPoint(x: bounds.width - pad - versionW, y: midY))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - SSID Manager
//
// Owns the CLLocationManager and exposes a synchronous currentSSID() that works
// once the user has granted Location Services access (required on macOS 10.15+
// for any API that reads the connected Wi-Fi network name).

final class SSIDManager: NSObject, CLLocationManagerDelegate {

    static let shared = SSIDManager()

    private let locationManager = CLLocationManager()

    /// Called on the main thread whenever the authorization status changes.
    var onAuthorizationChange: ((Bool) -> Void)?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways
    }

    private override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }

    /// Presents the macOS Location Services permission dialog.
    /// Requires NSLocationUsageDescription in Info.plist AND
    /// com.apple.security.personal-information.location in the .entitlements file.
    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Returns the current SSID synchronously when Location Services are authorized,
    /// nil otherwise (caller should fall back to the airport CLI tool).
    func currentSSID() -> String? {
        guard isAuthorized else { return nil }
        return CWWiFiClient.shared().interface()?.ssid()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Called on the main thread per Apple documentation.
        authorizationStatus = manager.authorizationStatus
        NotificationCenter.default.post(name: .locationAuthorizationChanged, object: nil)
        onAuthorizationChange?(isAuthorized)
    }
}

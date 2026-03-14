import SwiftUI
import AppKit

@main
struct OnlineIndicatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem!
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var launchPopover: NSPopover?

    private var menuHeaderView: MenuHeaderView?
    private var wifiMenuItem: NSMenuItem?
    private var ipv4MenuItem: NSMenuItem?
    private var ipv6MenuItem: NSMenuItem?

    private var currentStatus: AppState.ConnectionStatus = .noNetwork
    private var lastWifiName: String?
    private var lastIPv4: String?
    private var lastIPv6: String?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {

        UserDefaults.standard.set(Date(), forKey: "lastLaunchDate")

        if UserDefaults.standard.object(forKey: "refreshInterval") == nil {
            showOnboarding()
        } else {
            startApp()
        }
    }

    private func startApp() {
        setupStatusItem()

        AppState.shared.statusUpdateHandler = { [weak self] status in
            self?.currentStatus = status
            self?.updateIcon(for: status)
        }

        AppState.shared.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showLaunchTooltip()
        }

        NotificationCenter.default.addObserver(
            forName: .iconPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.updateIcon(for: self.currentStatus)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        let addresses = IPAddressProvider.current()
        lastWifiName = addresses.wifiName
        lastIPv4 = addresses.ipv4
        lastIPv6 = addresses.ipv6

        wifiMenuItem?.attributedTitle = ipAttributedString(
            label: "WiFi",
            value: addresses.wifiName ?? "Unavailable",
            available: addresses.wifiName != nil
        )
        ipv4MenuItem?.attributedTitle = ipAttributedString(
            label: "IPv4",
            value: addresses.ipv4 ?? "Unavailable",
            available: addresses.ipv4 != nil
        )
        ipv6MenuItem?.attributedTitle = ipAttributedString(
            label: "IPv6",
            value: addresses.ipv6 ?? "Unavailable",
            available: addresses.ipv6 != nil
        )
    }

    // MARK: - Menu Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .noNetwork)

        let menu = NSMenu()
        menu.delegate = self
        menu.minimumWidth = 260

        let header = MenuHeaderView(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        menuHeaderView = header
        let headerItem = NSMenuItem()
        headerItem.view = header
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(.separator())

        let wifiItem = NSMenuItem(title: "", action: #selector(copyWifiName), keyEquivalent: "")
        wifiItem.target = self
        wifiItem.toolTip = "Click to copy"
        wifiItem.attributedTitle = ipAttributedString(label: "WiFi", value: "Loading…", available: false)
        wifiMenuItem = wifiItem
        menu.addItem(wifiItem)

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

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit \(AppInfo.appName)", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
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

    // MARK: - Copy actions

    @objc private func copyWifiName() {
        guard let name = lastWifiName else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        showCopiedTooltip(text: "WiFi Copied")
    }

    @objc private func copyIPv4() {
        guard let ip = lastIPv4 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        showCopiedTooltip(text: "IPv4 Copied")
    }

    @objc private func copyIPv6() {
        guard let ip = lastIPv6 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        showCopiedTooltip(text: "IPv6 Copied")
    }

    // MARK: - Popover helper
    private func showStatusPopover<Content: View>(content: Content, autoDismissAfter delay: Double) {
        guard let button = statusItem.button else { return }

        let hostingView = NSHostingView(rootView: content)
        let size = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: size)

        let controller = NSViewController()
        controller.view = hostingView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = size
        popover.contentViewController = controller

        let anchor = NSRect(x: button.bounds.midX - 1, y: 0,
                            width: 2, height: button.bounds.height)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { popover.performClose(nil) }
        }
    }

    private func showCopiedTooltip(text: String) {
        let content = HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.system(size: 13))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        showStatusPopover(content: content, autoDismissAfter: 1.5)
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.startApp()
            self?.onboardingWindow = nil
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
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
            color      = pref.color
        } else {
            switch status {
            case .connected: symbolName = "wifi"; color = .systemGreen
            case .blocked:   symbolName = "wifi"; color = .systemYellow
            case .noNetwork: symbolName = "wifi.slash";       color = .systemRed
            }
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let baseImage = NSImage(systemSymbolName: symbolName,
                                      accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }

        let tinted = baseImage.copy() as! NSImage
        tinted.lockFocus()
        color.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let rawLabel  = String(pref.menuLabel.prefix(15)).trimmingCharacters(in: .whitespaces)
        let showLabel = pref.menuLabelEnabled && !rawLabel.isEmpty
        let barHeight = NSStatusBar.system.thickness
        let iconSize  = tinted.size
        let finalImage: NSImage

        if showLabel {
            let font = NSFont.menuBarFont(ofSize: 12)

            let attachment = NSTextAttachment()
            attachment.image = tinted
            attachment.bounds = NSRect(
                x: 0,
                y: (font.capHeight - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font:            font,
                .foregroundColor: NSColor.labelColor,
                .baselineOffset:  0
            ]

            let full = NSMutableAttributedString()
            full.append(NSAttributedString(attachment: attachment))
            full.append(NSAttributedString(string: " " + rawLabel, attributes: textAttrs))

            button.image           = nil
            button.imagePosition   = .noImage
            button.attributedTitle = full
            return
        } else {
            finalImage = NSImage(size: NSSize(width: barHeight, height: barHeight),
                                 flipped: false) { rect in
                let ox = (rect.width  - iconSize.width)  / 2
                let oy = (rect.height - iconSize.height) / 2
                tinted.draw(in: NSRect(x: ox, y: oy,
                                       width: iconSize.width, height: iconSize.height))
                return true
            }
        }

        finalImage.isTemplate  = false
        button.image           = finalImage
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition   = .imageOnly
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .settingsWindowDidBecomeKey, object: nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = AppInfo.appName
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Launch tooltip

    private func showLaunchTooltip() {
        let content = Text("\(AppInfo.appName) is running")
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        showStatusPopover(content: content, autoDismissAfter: 2.0)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Compact Menu Header

private class MenuHeaderView: NSView {

    private let nameLabel    = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        nameLabel.stringValue    = AppInfo.appName
        versionLabel.stringValue = AppInfo.fullVersionString

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .labelColor
        addSubview(nameLabel)

        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        addSubview(versionLabel)
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 14
        let midY: CGFloat = (bounds.height - 14) / 2

        nameLabel.frame = NSRect(x: pad, y: midY, width: bounds.width * 0.6, height: 14)

        versionLabel.sizeToFit()
        versionLabel.frame = NSRect(
            x: bounds.width - pad - versionLabel.frame.width,
            y: midY + 0.5,
            width: versionLabel.frame.width,
            height: 13
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

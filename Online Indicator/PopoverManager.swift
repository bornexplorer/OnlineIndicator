import SwiftUI
import AppKit

// MARK: - PopoverManager
//
// Centralises all status-item popover creation, content, and dismissal.
// Initialised with a button provider closure so it always resolves the
// current NSStatusBarButton without holding a strong reference to it.

final class PopoverManager: NSObject, NSPopoverDelegate {

    private var activePopover: NSPopover?
    private var resignActiveObserver: NSObjectProtocol?
    private let buttonProvider: () -> NSStatusBarButton?

    init(buttonProvider: @escaping () -> NSStatusBarButton?) {
        self.buttonProvider = buttonProvider
    }

    // MARK: - Core show / dismiss

    var isShowing: Bool { activePopover != nil }

    private func show<Content: View>(content: Content, persistent: Bool, autoDismissAfter delay: Double) {
        guard let button = buttonProvider() else { return }

        dismiss()

        let hostingView = NSHostingView(rootView: content)
        let size = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: size)

        let controller = NSViewController()
        controller.view = hostingView

        let popover = NSPopover()
        popover.behavior = persistent ? .applicationDefined : .transient
        popover.animates  = true
        popover.contentSize = size
        popover.contentViewController = controller
        popover.delegate = self

        let anchor = NSRect(x: button.bounds.midX - 1, y: 0,
                            width: 2, height: button.bounds.height)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)

        activePopover = popover

        if persistent {
            // Activate the app so didResignActiveNotification fires on outside click.
            // Brief delay avoids this click from immediately deactivating the app.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak popover] in
                popover?.performClose(nil)
                if self?.activePopover === popover { self?.activePopover = nil }
            }
        }
    }

    /// Show a persistent popover that dismisses on outside click and Escape.
    func showPersistent<Content: View>(content: Content) {
        show(content: content, persistent: true, autoDismissAfter: 0)
        installResignActiveObserver()
    }

    func dismiss() {
        activePopover?.performClose(nil)
        activePopover = nil
        removeResignActiveObserver()
    }

    // MARK: - Resign-active observer (outside-click dismissal)

    private func installResignActiveObserver() {
        removeResignActiveObserver()
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeResignActiveObserver() {
        if let obs = resignActiveObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        resignActiveObserver = nil
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover,
              closed === activePopover else { return }
        activePopover = nil
        removeResignActiveObserver()
    }

    // MARK: - Named notifications

    func showText(_ text: String, autoDismissAfter delay: Double = 1.5) {
        let content = Text(text)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        show(content: content, persistent: delay == 0, autoDismissAfter: delay)
    }

    func showPersistentText(_ text: String) {
        showText(text, autoDismissAfter: 0)
    }

    func showChecking() {
        let content = HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.85)
            Text("Checking…")
                .font(.system(size: 13))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        show(content: content, persistent: true, autoDismissAfter: 0)
    }

    func showConnectionStatus(_ status: AppState.ConnectionStatus) {
        let text: String = switch status {
        case .connected: "Connected"
        case .blocked:   "Connection Blocked"
        case .noNetwork: "No Network"
        }
        showText(text)
    }

    func showCopied(_ label: String) {
        showText(label)
    }

    func showLaunchTooltip() {
        showText("\(AppInfo.appName) running", autoDismissAfter: 2.0)
    }

    func showWiFiToggling(turningOn: Bool) {
        showPersistentText(turningOn ? "Turning On Wi-Fi…" : "Turning Off Wi-Fi…")
    }

    func showWiFiPowerChanged(isOn: Bool) {
        showText(isOn ? "Wi-Fi On" : "Wi-Fi Off", autoDismissAfter: 1.0)
    }

    func showOpeningWiFiSettings() {
        showText("Opening Wi-Fi Settings")
    }

    func showOpeningVPNSettings() {
        showText("Opening Network Settings")
    }

    func showNoNetwork() {
        showText("No Network")
    }

    func showNetworkSwitched(to ssid: String) {
        showText("Switched to \u{201C}\(ssid)\u{201D}", autoDismissAfter: 2.0)
    }
}

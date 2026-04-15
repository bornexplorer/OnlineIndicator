import SwiftUI
import AppKit

// MARK: - PopoverManager
//
// Centralises all status-item popover creation, content, and dismissal.
// Initialised with a button provider closure so it always resolves the
// current NSStatusBarButton without holding a strong reference to it.

final class PopoverManager {

    private var activePopover: NSPopover?
    private let buttonProvider: () -> NSStatusBarButton?

    init(buttonProvider: @escaping () -> NSStatusBarButton?) {
        self.buttonProvider = buttonProvider
    }

    // MARK: - Core show / dismiss

    func show<Content: View>(content: Content, autoDismissAfter delay: Double) {
        guard let button = buttonProvider() else { return }

        activePopover?.performClose(nil)
        activePopover = nil

        let hostingView = NSHostingView(rootView: content)
        let size = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: size)

        let controller = NSViewController()
        controller.view = hostingView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates  = true
        popover.contentSize = size
        popover.contentViewController = controller

        let anchor = NSRect(x: button.bounds.midX - 1, y: 0,
                            width: 2, height: button.bounds.height)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)

        activePopover = popover

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak popover] in
                popover?.performClose(nil)
                if self?.activePopover === popover { self?.activePopover = nil }
            }
        }
    }

    func dismiss() {
        activePopover?.performClose(nil)
        activePopover = nil
    }

    // MARK: - Named notifications

    func showText(_ text: String, autoDismissAfter delay: Double = 1.5) {
        let content = Text(text)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        show(content: content, autoDismissAfter: delay)
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
        show(content: content, autoDismissAfter: 0)
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

    /// Shows the startup greeting. Duration is 2 s so the AppDelegate's
    /// 2.3 s gate timer always fires after the tooltip has auto-dismissed.
    func showLaunchTooltip() {
        showText("\(AppInfo.appName) running", autoDismissAfter: 2.0)
    }

    /// "Turning On Wi-Fi…" / "Turning Off Wi-Fi…" — persists until dismissed.
    func showWiFiToggling(turningOn: Bool) {
        showPersistentText(turningOn ? "Turning On Wi-Fi…" : "Turning Off Wi-Fi…")
    }

    /// "Wi-Fi On" / "Wi-Fi Off" — shown after a power-state change completes.
    func showWiFiPowerChanged(isOn: Bool) {
        showText(isOn ? "Wi-Fi On" : "Wi-Fi Off", autoDismissAfter: 1.0)
    }

    /// "Opening Wi-Fi Settings" — brief acknowledgement before the pref pane opens.
    func showOpeningWiFiSettings() {
        showText("Opening Wi-Fi Settings")
    }

    /// "Opening VPN Settings" — brief acknowledgement before the pref pane opens.
    func showOpeningVPNSettings() {
        showText("Opening Network Settings")
    }

    /// "No Network" — shown when SSID is lost while Wi-Fi is still powered on.
    func showNoNetwork() {
        showText("No Network")
    }

    /// "Switched to 'NetworkName'" — shown when the user joins a different network.
    func showNetworkSwitched(to ssid: String) {
        showText("Switched to \u{201C}\(ssid)\u{201D}", autoDismissAfter: 2.0)
    }
}

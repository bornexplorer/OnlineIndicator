import SwiftUI
import AppKit
import CoreWLAN

struct HistoryPopoverView: View {

    var dismissAction: (() -> Void)?

    @State private var currentStatus: AppState.ConnectionStatus = .noNetwork
    @State private var wifiOn: Bool = CWWiFiClient.shared().interface()?.powerOn() ?? false
    @State private var ipv4: String? = nil
    @State private var ipv6: String? = nil
    @State private var ssid: String? = nil
    @State private var showWifiName: Bool = false
    @State private var hideIPv4: Bool = false
    @State private var hideIPv6: Bool = false

    private var statusText: String {
        switch currentStatus {
        case .connected: return "Connected"
        case .blocked:   return "Blocked"
        case .noNetwork: return "No Network"
        }
    }

    private var statusColor: Color {
        switch currentStatus {
        case .connected: return Color(IconPreferences.slot(for: .connected).color)
        case .blocked:   return Color(IconPreferences.slot(for: .blocked).color)
        case .noNetwork: return Color(IconPreferences.slot(for: .noNetwork).color)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ---- History chart ----
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                HistoryChartView()
                    .frame(width: 840, height: 440)
            }

            Divider().padding(.horizontal, 14)

            // ---- Menu items ----
            VStack(spacing: 0) {
                // Wi-Fi toggle row
                wifiToggleRow

                // Wi-Fi Settings…
                menuButton(
                    title: "Wi-Fi Settings…",
                    image: nil,
                    action: {
                        dismissAction?()
                        openWiFiSettings()
                    }
                )

                separator

                // Network header
                sectionHeader("Network")

                // Wi-Fi name
                if showWifiName {
                    wifiNameRow
                }

                // IP rows
                if !hideIPv4 {
                    menuButton(title: "IPv4", subtitle: ipv4 ?? "Unavailable", action: { copyIP(ipv4, label: "IPv4") })
                }
                if !hideIPv6 {
                    menuButton(title: "IPv6", subtitle: ipv6 ?? "Unavailable", action: { copyIP(ipv6, label: "IPv6") })
                }

                separator

                // Settings
                menuButton(
                    title: "Settings",
                    image: "gear",
                    action: {
                        dismissAction?()
                        openAppSettings()
                    }
                )

                // Quit
                menuButton(
                    title: "Quit",
                    image: "power",
                    action: {
                        NSApplication.shared.terminate(nil)
                    }
                )

                separator

                // App info
                appInfoRow
            }
        }
        .frame(width: 840)
        .onAppear { refresh() }
    }

    // MARK: - Wi-Fi Toggle Row

    private var wifiToggleRow: some View {
        HStack(spacing: 0) {
            Image(systemName: wifiOn ? "wifi" : "wifi.slash")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(wifiOn ? .primary : .secondary)
                .frame(width: 20)
            Text("Wi-Fi")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: $wifiOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: wifiOn) { _, newValue in
                    toggleWiFi(on: newValue)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - Wi-Fi Name Row

    private var wifiNameRow: some View {
        HStack(spacing: 0) {
            if let ssid {
                HStack(spacing: 0) {
                    Text("Wi-Fi")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("   ")
                        .font(.system(size: 11, design: .monospaced))
                    Text(ssid)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text("Requires Location Access")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - App Info Row

    private var appInfoRow: some View {
        HStack {
            Text(AppInfo.appName)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(AppInfo.marketingVersion)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - Reusable components

    private func menuButton(title: String, subtitle: String? = nil, image: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if let image {
                    Image(systemName: image)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var separator: some View {
        Divider().padding(.leading, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    // MARK: - Actions

    private func toggleWiFi(on: Bool) {
        guard let iface = CWWiFiClient.shared().interface() else { return }
        do {
            try iface.setPower(on)
        } catch {
            wifiOn = iface.powerOn()
        }
    }

    private func copyIP(_ ip: String?, label: String) {
        guard let ip else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
    }

    private func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAppSettings() {
        NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
    }

    // MARK: - Refresh

    private func refresh() {
        currentStatus = AppState.shared.currentStatus
        wifiOn = CWWiFiClient.shared().interface()?.powerOn() ?? false
        ssid = SSIDManager.shared.currentSSID()
        let addrs = IPAddressProvider.current()
        ipv4 = addrs.ipv4
        ipv6 = addrs.ipv6
        showWifiName = UserDefaults.standard.bool(forKey: "showWifiNameInMenu")
        hideIPv4 = UserDefaults.standard.bool(forKey: "hideIPv4")
        hideIPv6 = UserDefaults.standard.bool(forKey: "hideIPv6")
    }
}

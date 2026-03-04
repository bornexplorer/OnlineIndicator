import SwiftUI
import AppKit

struct SettingsView: View {

    @State private var selectedTab      = 0
    @State private var interval: Double = {
        let v = UserDefaults.standard.double(forKey: "refreshInterval")
        return v == 0 ? 60 : v
    }()
    @State private var intervalText     = ""
    @State private var intervalSaved    = false
    @State private var pingURL          = ""
    @State private var pingURLSaved     = false
    @State private var isLaunchEnabled  = false

    enum UpdateStatus: Equatable {
        case idle, checking
        case available(tag: String)
        case upToDate
        case error(String)
    }
    @State private var updateStatus: UpdateStatus = .idle

    @State private var connectedSlot     = IconPreferences.slot(for: .connected)
    @State private var blockedSlot       = IconPreferences.slot(for: .blocked)
    @State private var noNetworkSlot     = IconPreferences.slot(for: .noNetwork)
    @State private var showSymbolBrowser = false
    @State private var showCopiedToast   = false
    @State private var copiedSymbolName  = ""

    var body: some View {
        VStack(spacing: 0) {

            Picker("", selection: $selectedTab) {
                Label("General",    systemImage: "gearshape.fill").tag(0)
                Label("Appearance", systemImage: "paintbrush.fill").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Group {
                if selectedTab == 0 {
                    generalTab
                } else {
                    appearanceTab
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selectedTab)
        }
        .frame(width: 440)
        .background(Color(.windowBackgroundColor))

        .sheet(isPresented: $showSymbolBrowser) {
            SymbolBrowserView()
        }

        .overlay(alignment: .bottom) {
            if showCopiedToast {
                HStack(spacing: 8) {
                    Image(systemName: copiedSymbolName)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\"\(copiedSymbolName)\" copied")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Paste it into an Appearance symbol field above")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .symbolCopied)) { note in
            copiedSymbolName = note.object as? String ?? ""
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showCopiedToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.25)) { showCopiedToast = false }
            }
        }
        .onAppear {
            isLaunchEnabled = LoginItemManager.shared.isEnabled()
            intervalText    = formatInterval(interval)
            pingURL         = UserDefaults.standard.string(forKey: "pingURL") ?? ""
            connectedSlot   = IconPreferences.slot(for: .connected)
            blockedSlot     = IconPreferences.slot(for: .blocked)
            noNetworkSlot   = IconPreferences.slot(for: .noNetwork)
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidBecomeKey)) { _ in
            isLaunchEnabled = LoginItemManager.shared.isEnabled()
            connectedSlot   = IconPreferences.slot(for: .connected)
            blockedSlot     = IconPreferences.slot(for: .blocked)
            noNetworkSlot   = IconPreferences.slot(for: .noNetwork)
        }
    }

    // MARK: - Tab 1: General

    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 24) {

                SettingsSection(title: "General") {
                    SettingsRow(
                        icon: "arrow.clockwise.circle.fill",
                        iconColor: .red,
                        title: "Launch at Login",
                        subtitle: "Start automatically when you log in"
                    ) {
                        Toggle("", isOn: $isLaunchEnabled)
                            .labelsHidden()
                            .onChange(of: isLaunchEnabled) { _, newValue in
                                LoginItemManager.shared.setEnabled(newValue)
                            }
                    }

                    Divider().padding(.leading, 56)

                    SettingsRow(
                        icon: "arrow.down.circle.fill",
                        iconColor: .blue,
                        title: "Check for Updates",
                        subtitle: "Version \(AppInfo.marketingVersion) (Build \(AppInfo.buildVersion))"
                    ) {
                        HStack(spacing: 8) {
                            if updateStatus == .checking {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                            }

                            Button(updateStatus == .checking ? "Checking…" : "Check") {
                                checkForUpdates()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(updateStatus == .checking)

                            switch updateStatus {
                            case .upToDate:
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Up to date")
                                        .foregroundStyle(.green)
                                }
                                .font(.system(size: 12))
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                            case .available(let tag):
                                Button("Update to \(tag)") { openLatestRelease() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            case .error(let msg):
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                                    .transition(.opacity)
                            default:
                                EmptyView()
                            }
                        }
                    }
                }

                SettingsSection(title: "Monitoring") {
                    SettingsRow(
                        icon: "clock.fill",
                        iconColor: .orange,
                        title: "Check Interval",
                        subtitle: "How often to probe the connection"
                    ) {
                        HStack(spacing: 8) {
                            TextField("", text: $intervalText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)

                            Text("sec")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))

                            Button("Apply") { applyInterval() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                            if intervalSaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        HStack(spacing: 6) {
                            ForEach([("30s", 30.0), ("1m", 60.0), ("2m", 120.0), ("5m", 300.0)], id: \.1) { lbl, val in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        interval     = val
                                        intervalText = formatInterval(val)
                                    }
                                } label: {
                                    Text(lbl)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(interval == val
                                                      ? Color.accentColor.opacity(0.15)
                                                      : Color.primary.opacity(0.07))
                                        )
                                        .foregroundStyle(interval == val ? Color.accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 56)

                    SettingsRow(
                        icon: "target",
                        iconColor: .green,
                        title: "Ping URL",
                        subtitle: "URL used to test outbound connectivity"
                    ) {
                        EmptyView()
                    }

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        HStack(spacing: 8) {
                            TextField(ConnectivityChecker.defaultURLString, text: $pingURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            Button("Apply") { applyPingURL() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                            if pingURLSaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.trailing, 18)
                    }
                    .padding(.bottom, 4)

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        Button("Restore Default") { restoreDefaultPingURL() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .disabled(pingURL.isEmpty)
                            .opacity(pingURL.isEmpty ? 0.4 : 1)
                        Spacer()
                    }
                    .padding(.bottom, 12)
                }

                footerView
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Tab 2: Appearance

    private var appearanceTab: some View {
        ScrollView {
            VStack(spacing: 24) {

                SettingsSection(title: "Appearance") {
                    VStack(spacing: 0) {
                        IconSlotRow(
                            label: "Connected",
                            statusDescription: "Outbound connection reachable",
                            slot: $connectedSlot
                        ) {
                            IconPreferences.save(connectedSlot, for: .connected)
                        }

                        Divider().padding(.leading, 14)

                        IconSlotRow(
                            label: "Blocked",
                            statusDescription: "Network up but traffic is blocked",
                            slot: $blockedSlot
                        ) {
                            IconPreferences.save(blockedSlot, for: .blocked)
                        }

                        Divider().padding(.leading, 14)

                        IconSlotRow(
                            label: "No Network",
                            statusDescription: "No active network interface",
                            slot: $noNetworkSlot
                        ) {
                            IconPreferences.save(noNetworkSlot, for: .noNetwork)
                        }

                        Divider().padding(.leading, 14)

                        HStack {
                            Button("SF Symbols") { showSymbolBrowser = true }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Reset to Defaults") {
                                withAnimation {
                                    IconPreferences.resetAll()
                                    connectedSlot  = IconPreferences.slot(for: .connected)
                                    blockedSlot    = IconPreferences.slot(for: .blocked)
                                    noNetworkSlot  = IconPreferences.slot(for: .noNetwork)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }

                footerView
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Shared footer

    private var footerView: some View {
        HStack(spacing: 4) {
            Text(AppInfo.appName)
            Text("·")
            Text(AppInfo.fullVersionString)
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func formatInterval(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    private func applyInterval() {
        let value = Double(intervalText) ?? 60
        interval  = value
        UserDefaults.standard.set(value, forKey: "refreshInterval")
        AppState.shared.restart()

        withAnimation { intervalSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { intervalSaved = false }
        }
    }

    private func applyPingURL() {
        let trimmed = pingURL.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: "pingURL")
        } else {
            UserDefaults.standard.set(trimmed, forKey: "pingURL")
        }

        withAnimation { pingURLSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { pingURLSaved = false }
        }
    }

    private func restoreDefaultPingURL() {
        UserDefaults.standard.removeObject(forKey: "pingURL")
        withAnimation { pingURL = "" }

        withAnimation { pingURLSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { pingURLSaved = false }
        }
    }

    private func checkForUpdates() {
        withAnimation { updateStatus = .checking }
        UpdateChecker.check { result in
            withAnimation {
                switch result {
                case .upToDate:
                    updateStatus = .upToDate
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation { updateStatus = .idle }
                    }
                case .updateAvailable(let tag, _, _, _):
                    updateStatus = .available(tag: tag)
                case .error(let msg):
                    updateStatus = .error(msg)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation { updateStatus = .idle }
                    }
                }
            }
        }
    }

    private func openLatestRelease() {
        UpdateChecker.check { result in
            if case .updateAvailable(_, _, let downloadURL, let pageURL) = result {
                NSWorkspace.shared.open(downloadURL ?? pageURL)
            }
        }
    }
}

// MARK: - Icon Slot Row

private struct IconSlotRow: View {

    let label: String
    let statusDescription: String
    @Binding var slot: IconPreferences.Slot
    let onChange: () -> Void

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(slot.color) },
            set: { slot.color = NSColor($0); onChange() }
        )
    }

    private var symbolIsValid: Bool {
        NSImage(systemSymbolName: slot.symbolName, accessibilityDescription: nil) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(statusDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .top, spacing: 10) {

                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(slot.color).opacity(0.15))
                        .frame(width: 32, height: 32)

                    if symbolIsValid {
                        Image(systemName: slot.symbolName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(slot.color))
                    } else {
                        Image(systemName: "questionmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {

                    TextField("SF Symbol name", text: Binding(
                        get: { slot.symbolName },
                        set: { slot.symbolName = $0; onChange() }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: 180)

                    if !symbolIsValid && !slot.symbolName.isEmpty {
                        Text("Symbol not found")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 6) {
                        TextField("Menu bar label (10 chars max)", text: Binding(
                            get: { slot.menuLabel },
                            set: { slot.menuLabel = String($0.prefix(10)); onChange() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 180)
                        .disabled(!slot.menuLabelEnabled)
                        .opacity(slot.menuLabelEnabled ? 1 : 0.4)

                        Toggle("", isOn: Binding(
                            get: { slot.menuLabelEnabled },
                            set: { slot.menuLabelEnabled = $0; onChange() }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                }

                Spacer()

                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 24, height: 24)
                    .padding(.top, 3)
                    .padding(.trailing, 14)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Section container

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color(.quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            )
        }
    }
}

// MARK: - Reusable row

private struct SettingsRow<Control: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(iconColor)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

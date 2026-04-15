import SwiftUI
import AppKit
import CoreLocation

struct SettingsView: View {

    @State private var selectedTab   = 0
    @State private var interval: Double = {
        let v = UserDefaults.standard.double(forKey: "refreshInterval")
        return v == 0 ? 60 : v
    }()
    @State private var intervalText    = ""
    @State private var intervalSaved   = false
    @State private var intervalInvalid = false
    @State private var pingURL         = ""
    @State private var pingURLSaved    = false
    @State private var pingURLInvalid  = false
    @State private var isLaunchEnabled = false

    @State private var leftRightClickEnabled = true
    @State private var leftClickAction       = "wifi"
    @State private var rightClickAction      = "menu"
    @State private var leftRightClickSwapped = false

    @State private var hideIPv4 = false
    @State private var hideIPv6 = false

    @State private var showWifiNameInMenu    = false
    @State private var useSSIDAsMenuBarLabel = false
    @State private var wifiNameInMenuSSID: String? = nil
    @State private var isLocationAuthorized: Bool = SSIDManager.shared.isAuthorized

    private enum SSIDFeature { case menuItem, menuBarLabel }
    @State private var ssidFeaturePendingAuth: SSIDFeature? = nil
    @State private var showLocationAlert       = false
    @State private var showLocationDeniedAlert = false
    @State private var showOverrideAlert       = false

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available(tag: String, pageURL: URL)
        case error(String)
    }
    @State private var updateStatus: UpdateStatus = .idle
    @State private var cachedPageURL: URL? = nil

    @State private var connectedSlot  = IconPreferences.slot(for: .connected)
    @State private var blockedSlot    = IconPreferences.slot(for: .blocked)
    @State private var noNetworkSlot  = IconPreferences.slot(for: .noNetwork)
    @State private var showSymbolBrowser = false
    @StateObject private var userSetsStore      = UserIconSetsStore()
    @State private var showSaveSetPanel         = false
    @State private var saveSetName              = ""
    @State private var suppressSaveButton       = false
    @State private var showSetSavedConfirmation = false

    @State private var wifiToggleShortcut:   KeyboardShortcut? = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.wifiToggleKey)
    @State private var wifiSettingsShortcut: KeyboardShortcut? = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.wifiSettingsKey)
    @State private var vpnSettingsShortcut:  KeyboardShortcut? = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.vpnSettingsKey)

    private let leftClickOptions: [(label: String, tag: String)] = [
        ("None",                         "none"),
        ("Open Wi-Fi Settings",          "wifi"),
        ("Open Network Settings",        "vpnSettings"),
        ("Check Connection Now",         "checkNow"),
        ("Toggle Wi-Fi On / Off",        "wifiToggle")
    ]

    private let rightClickOptions: [(label: String, tag: String)] = [
        ("Online Indicator Settings", "settings"),
        ("Online Indicator Menu",     "menu")
    ]

    private var leftRowLabel:  String { leftRightClickSwapped ? "Right click" : "Left click"  }
    private var rightRowLabel: String { leftRightClickSwapped ? "Left click"  : "Right click" }

    private func colorDiffers(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ac = a.usingColorSpace(.sRGB),
              let bc = b.usingColorSpace(.sRGB) else { return !a.isEqual(b) }
        return abs(ac.redComponent   - bc.redComponent)   > 0.001 ||
               abs(ac.greenComponent - bc.greenComponent) > 0.001 ||
               abs(ac.blueComponent  - bc.blueComponent)  > 0.001
    }

    private var isModifiedFromDefault: Bool {
        let dc = IconPreferences.defaultSlot(for: .connected)
        let db = IconPreferences.defaultSlot(for: .blocked)
        let dn = IconPreferences.defaultSlot(for: .noNetwork)
        return connectedSlot.symbolName  != dc.symbolName || colorDiffers(connectedSlot.color,  dc.color) ||
               connectedSlot.menuLabel   != dc.menuLabel  || connectedSlot.menuLabelEnabled != dc.menuLabelEnabled ||
               blockedSlot.symbolName    != db.symbolName || colorDiffers(blockedSlot.color,    db.color) ||
               blockedSlot.menuLabel     != db.menuLabel  || blockedSlot.menuLabelEnabled   != db.menuLabelEnabled ||
               noNetworkSlot.symbolName  != dn.symbolName || colorDiffers(noNetworkSlot.color,  dn.color) ||
               noNetworkSlot.menuLabel   != dn.menuLabel  || noNetworkSlot.menuLabelEnabled != dn.menuLabelEnabled
    }

    private var currentSlotsMatchAnySavedSet: Bool {
        let (c, b, n) = (connectedSlot, blockedSlot, noNetworkSlot)
        return userSetsStore.sets.contains { set in
            let (sc, sb, sn) = set.toSlots()
            return sc.symbolName == c.symbolName && !colorDiffers(sc.color, c.color) &&
                   sc.menuLabel  == c.menuLabel  && sc.menuLabelEnabled == c.menuLabelEnabled &&
                   sb.symbolName == b.symbolName && !colorDiffers(sb.color, b.color) &&
                   sb.menuLabel  == b.menuLabel  && sb.menuLabelEnabled == b.menuLabelEnabled &&
                   sn.symbolName == n.symbolName && !colorDiffers(sn.color, n.color) &&
                   sn.menuLabel  == n.menuLabel  && sn.menuLabelEnabled == n.menuLabelEnabled
        }
    }

    private var shouldShowSaveButton: Bool {
        isModifiedFromDefault && !suppressSaveButton &&
        !showSetSavedConfirmation && !currentSlotsMatchAnySavedSet
    }

    private func onSlotChanged() {
        if suppressSaveButton && !currentSlotsMatchAnySavedSet {
            withAnimation(.easeInOut(duration: 0.2)) {
                suppressSaveButton = false
                showSetSavedConfirmation = false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                TabBarButton(title: "General",    systemImage: "gearshape.fill",   tag: 0, selected: $selectedTab)
                TabBarButton(title: "Appearance", systemImage: "paintbrush.fill",  tag: 1, selected: $selectedTab)
                TabBarButton(title: "Shortcuts",  systemImage: "keyboard",         tag: 2, selected: $selectedTab)
                TabBarButton(title: "About",      systemImage: "info.circle.fill", tag: 3, selected: $selectedTab)
            }
            .padding(3)
            .background(Color(.quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            Group {
                if selectedTab == 0 { generalTab }
                else if selectedTab == 1 { appearanceTab }
                else if selectedTab == 2 { keyboardShortcutsTab }
                else { aboutTab }
            }
            .animation(.easeInOut(duration: 0.18), value: selectedTab)
        }
        .frame(width: 460)
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showSymbolBrowser) {
            SymbolBrowserView(
                store: userSetsStore,
                onSelect: { connected, blocked, noNetwork in
                    connectedSlot = connected; blockedSlot = blocked; noNetworkSlot = noNetwork
                    IconPreferences.save(connected,  for: .connected)
                    IconPreferences.save(blocked,    for: .blocked)
                    IconPreferences.save(noNetwork,  for: .noNetwork)
                    suppressSaveButton = true; showSetSavedConfirmation = false
                    showSaveSetPanel = false; saveSetName = ""
                }
            )
        }
        .onAppear {
            isLaunchEnabled       = LoginItemManager.shared.isEnabled()
            intervalText          = formatInterval(interval)
            pingURL               = UserDefaults.standard.string(forKey: "pingURL") ?? ""
            connectedSlot         = IconPreferences.slot(for: .connected)
            blockedSlot           = IconPreferences.slot(for: .blocked)
            noNetworkSlot         = IconPreferences.slot(for: .noNetwork)
            leftRightClickEnabled = UserDefaults.standard.bool(forKey: "leftRightClickEnabled")
            leftClickAction       = UserDefaults.standard.string(forKey: "leftClickAction")  ?? "wifi"
            rightClickAction      = UserDefaults.standard.string(forKey: "rightClickAction") ?? "menu"
            leftRightClickSwapped = UserDefaults.standard.bool(forKey: "leftRightClickSwapped")
            hideIPv4              = UserDefaults.standard.bool(forKey: "hideIPv4")
            hideIPv6              = UserDefaults.standard.bool(forKey: "hideIPv6")
            showWifiNameInMenu    = UserDefaults.standard.bool(forKey: "showWifiNameInMenu")
            useSSIDAsMenuBarLabel = UserDefaults.standard.bool(forKey: "useSSIDAsMenuBarLabel")
            wifiNameInMenuSSID    = SSIDManager.shared.currentSSID()
            isLocationAuthorized  = SSIDManager.shared.isAuthorized
            wifiToggleShortcut    = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.wifiToggleKey)
            wifiSettingsShortcut  = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.wifiSettingsKey)
            vpnSettingsShortcut   = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.vpnSettingsKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidBecomeKey)) { _ in
            isLaunchEnabled       = LoginItemManager.shared.isEnabled()
            connectedSlot         = IconPreferences.slot(for: .connected)
            blockedSlot           = IconPreferences.slot(for: .blocked)
            noNetworkSlot         = IconPreferences.slot(for: .noNetwork)
            leftRightClickEnabled = UserDefaults.standard.bool(forKey: "leftRightClickEnabled")
            leftClickAction       = UserDefaults.standard.string(forKey: "leftClickAction")  ?? "wifi"
            rightClickAction      = UserDefaults.standard.string(forKey: "rightClickAction") ?? "menu"
            leftRightClickSwapped = UserDefaults.standard.bool(forKey: "leftRightClickSwapped")
            hideIPv4              = UserDefaults.standard.bool(forKey: "hideIPv4")
            hideIPv6              = UserDefaults.standard.bool(forKey: "hideIPv6")
            showWifiNameInMenu    = UserDefaults.standard.bool(forKey: "showWifiNameInMenu")
            useSSIDAsMenuBarLabel = UserDefaults.standard.bool(forKey: "useSSIDAsMenuBarLabel")
            wifiNameInMenuSSID    = SSIDManager.shared.currentSSID()
            isLocationAuthorized  = SSIDManager.shared.isAuthorized
            wifiToggleShortcut    = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.wifiToggleKey)
            wifiSettingsShortcut  = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.wifiSettingsKey)
            vpnSettingsShortcut   = KeyboardShortcutManager.shared.shortcut(for: KeyboardShortcutManager.vpnSettingsKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationAuthorizationChanged)) { _ in
            let authorized = SSIDManager.shared.isAuthorized
            isLocationAuthorized = authorized
            if !authorized {
                showWifiNameInMenu = false
                wifiNameInMenuSSID = nil
                if useSSIDAsMenuBarLabel {
                    commitWifiNameAsLabel(false)
                }
            } else {
                wifiNameInMenuSSID = SSIDManager.shared.currentSSID()
            }
            guard authorized, let pending = ssidFeaturePendingAuth else { return }
            ssidFeaturePendingAuth = nil
            switch pending {
            case .menuItem:
                commitWifiNameInMenu(true)
            case .menuBarLabel:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showOverrideAlert = true
                }
            }
        }
        .alert("Location Access Needed", isPresented: $showLocationAlert) {
            Button("Allow Access") {
                SSIDManager.shared.requestAuthorization()
            }
            Button("Not Now", role: .cancel) {
                ssidFeaturePendingAuth = nil
            }
        } message: {
            Text("To read your Wi-Fi network name, \(AppInfo.appName) needs Location Services access. \n\nYour location is never stored or shared. macOS only uses it to determine which Wi-Fi network you're connected to.")
        }
        .alert("Location Access Disabled", isPresented: $showLocationDeniedAlert) {
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {
                ssidFeaturePendingAuth = nil
            }
        } message: {
            Text("Location Services are currently disabled for \(AppInfo.appName) or for this Mac. macOS requires this to identify which Wi-Fi network you're connected to — your location is never stored or shared.\n\nEnable it in System Settings → Privacy & Security → Location Services.")
        }
        .alert("Override Menu Bar Labels?", isPresented: $showOverrideAlert) {
            Button("Enable") { commitWifiNameAsLabel(true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your Wi-Fi network name will replace the custom menu bar label for the Connected and Blocked states. Your custom labels are preserved and restored if you turn this off.")
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 24) {

                SettingsSection(title: "General", trailing: {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit Online Indicator", systemImage: "power")
                            .font(.system(size: 11)).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }) {
                    SettingsRow(icon: "arrow.clockwise.circle.fill", iconColor: .yellow,
                                title: "Launch at Login",
                                subtitle: "Opens automatically when your Mac starts up") {
                        Toggle("", isOn: $isLaunchEnabled).labelsHidden()
                            .onChange(of: isLaunchEnabled) { _, v in LoginItemManager.shared.setEnabled(v) }
                    }

                    Divider().padding(.leading, 56)

                    SettingsRow(icon: "arrow.up.circle.fill", iconColor: .blue,
                                title: "Check for Updates",
                                subtitle: "Version \(AppInfo.marketingVersion) (Build \(AppInfo.buildVersion))") {
                        updateControl
                    }

                    if case .error(let msg) = updateStatus {
                        HStack(alignment: .top, spacing: 0) {
                            Spacer().frame(width: 56)
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red).font(.system(size: 11)).padding(.top, 1)
                                Text(msg)
                                    .foregroundStyle(.red).font(.system(size: 11))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.trailing, 14)
                        }
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                SettingsSection(title: "Monitoring") {

                    SettingsRow(icon: "clock.fill", iconColor: .orange,
                                title: "Check Interval",
                                subtitle: "How often the app checks if you're connected") {
                        EmptyView()
                    }

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                ForEach([("30s", 30.0), ("1m", 60.0), ("2m", 120.0), ("5m", 300.0)], id: \.1) { lbl, val in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            interval = val; intervalText = formatInterval(val); intervalInvalid = false
                                        }
                                        UserDefaults.standard.set(val, forKey: "refreshInterval")
                                        AppState.shared.restart()
                                        withAnimation { intervalSaved = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation { intervalSaved = false }
                                        }
                                    } label: {
                                        Text(lbl).font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(RoundedRectangle(cornerRadius: 6)
                                                .fill(interval == val ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.07)))
                                            .foregroundStyle(interval == val ? Color.accentColor : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                TextField("", text: $intervalText)
                                    .textFieldStyle(.roundedBorder).frame(width: 56).multilineTextAlignment(.trailing)
                                    .onChange(of: intervalText) { _, v in
                                        let d = v.filter { $0.isNumber }
                                        if d != v { intervalText = d }
                                        if intervalInvalid { intervalInvalid = false }
                                    }
                                Text("sec").foregroundStyle(.secondary).font(.system(size: 12))
                                if intervalSaved {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 16))
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Button("Apply") { applyInterval() }.buttonStyle(.bordered).controlSize(.small)
                                        .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .animation(.easeInOut(duration: 0.18), value: intervalSaved)
                        }
                        .padding(.trailing, 14)
                    }
                    .padding(.bottom, 10)

                    Divider().padding(.leading, 56)

                    SettingsRow(icon: "target", iconColor: .green,
                                title: "Ping URL",
                                subtitle: "The address the app visits to test your connection") { EmptyView() }

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                TextField(ConnectivityChecker.defaultURLString, text: $pingURL)
                                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                                    .onChange(of: pingURL) { _, _ in pingURLInvalid = false }
                                if pingURLSaved {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 16))
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Button("Apply") { applyPingURL() }.buttonStyle(.bordered).controlSize(.small)
                                        .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .animation(.easeInOut(duration: 0.18), value: pingURLSaved)
                            if pingURLInvalid {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                                    Text("Enter a valid URL").font(.system(size: 10))
                                }
                                .foregroundStyle(.red).transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.trailing, 18).animation(.easeInOut(duration: 0.18), value: pingURLInvalid)
                    }
                    .padding(.bottom, 4)

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        Button("Restore Default") { restoreDefaultPingURL() }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                            .disabled(pingURL.isEmpty).opacity(pingURL.isEmpty ? 0.4 : 1)
                        Spacer()
                    }
                    .padding(.bottom, 12)
                }

                SettingsSection(title: "Icon & Menu Options") {
                    SettingsRow(icon: "cursorarrow.rays", iconColor: .red,
                                title: "Click Actions",
                                subtitle: "Assign actions to left and right click") {
                        Toggle("", isOn: $leftRightClickEnabled).labelsHidden()
                            .onChange(of: leftRightClickEnabled) { _, v in
                                UserDefaults.standard.set(v, forKey: "leftRightClickEnabled")
                            }
                    }

                    ClickActionsBlock(
                        leftLabel:    leftRowLabel,  rightLabel:   rightRowLabel,
                        leftAction:   $leftClickAction, rightAction: $rightClickAction,
                        isSwapped:    $leftRightClickSwapped,
                        leftOptions:  leftClickOptions, rightOptions: rightClickOptions,
                        enabled:      leftRightClickEnabled,
                        onLeftChanged:  { UserDefaults.standard.set(leftClickAction, forKey: "leftClickAction") },
                        onRightChanged: { UserDefaults.standard.set(rightClickAction,      forKey: "rightClickAction") },
                        onSwapChanged:  { UserDefaults.standard.set(leftRightClickSwapped, forKey: "leftRightClickSwapped") }
                    )

                    Divider().padding(.leading, 56)

                    SettingsRow(icon: "wifi", iconColor: .blue,
                                title: "Network Name in Menu",
                                subtitle: "Show your connected network name in the dropdown menu") {
                        wifiNameInMenuControl
                    }

                    if showWifiNameInMenu {
                        wifiNameSubsectionView
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Divider().padding(.leading, 56)

                    SettingsRow(icon: "eye.slash", iconColor: .gray,
                                title: "Hide IP Addresses",
                                subtitle: "Remove IP address rows from the dropdown menu") {
                        EmptyView()
                    }

                    IPHideBlock(
                        hideIPv4: $hideIPv4,
                        hideIPv6: $hideIPv6,
                        onIPv4Changed: { UserDefaults.standard.set(hideIPv4, forKey: "hideIPv4") },
                        onIPv6Changed: { UserDefaults.standard.set(hideIPv6, forKey: "hideIPv6") }
                    )
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Wi-Fi Name in Menu Control

    @ViewBuilder
    private var wifiNameInMenuControl: some View {
        if showWifiNameInMenu {
            Button("Disable") {
                handleShowWifiNameInMenuToggle(false)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button("Enable") {
                handleShowWifiNameInMenuToggle(true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Wi-Fi Name Subsection

    private var wifiNameSubsectionView: some View {
        HStack(spacing: 10) {
            if let ssid = wifiNameInMenuSSID {
                Text(ssid)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Accessible")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Network name unavailable")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if isLocationAuthorized {
                    Button("Fetch") {
                        wifiNameInMenuSSID = SSIDManager.shared.currentSSID()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Grant Access") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(.leading, 56)
        .padding(.trailing, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Update control

    @ViewBuilder
    private var updateControl: some View {
        Group {
            switch updateStatus {
            case .idle:
                Button("Check") { checkForUpdates() }
                    .buttonStyle(.bordered).controlSize(.small)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                    Text("Checking…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            case .upToDate:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Up to date").foregroundStyle(.green)
                }.font(.system(size: 12))
            case .available(let tag, _):
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(tag) available")
                            .foregroundStyle(.green)
                    }
                    .font(.system(size: 12))
                    .fixedSize()
                    Button {
                        openPageURL()
                    } label: {
                        HStack(spacing: 3) {
                            Text("View on GitHub")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            case .error:
                Button("Retry") { checkForUpdates() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: updateStatus)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Appearance") {
                    VStack(spacing: 0) {

                        SettingsRow(icon: "character.cursor.ibeam", iconColor: .blue,
                                    title: "Use Wi-Fi Name as Label",
                                    subtitle: "Overrides the Connected & Blocked states label with your network name") {
                            Toggle("", isOn: Binding(
                                get: { useSSIDAsMenuBarLabel },
                                set: { handleUseSSIDAsMenuBarLabelToggle($0) }
                            )).labelsHidden()
                        }
                        .opacity(showWifiNameInMenu ? 1 : 0)
                        .frame(height: showWifiNameInMenu ? nil : 0)
                        .clipped()
                        .animation(.easeInOut(duration: 0.2), value: showWifiNameInMenu)

                        Divider().padding(.leading, 14)
                            .opacity(showWifiNameInMenu ? 1 : 0)
                            .frame(height: showWifiNameInMenu ? nil : 0)
                            .clipped()
                            .animation(.easeInOut(duration: 0.2), value: showWifiNameInMenu)

                        IconSlotRow(label: "Connected",
                                    statusDescription: "Internet access is available and this Mac is online",
                                    defaultSlot: IconPreferences.defaultSlot(for: .connected),
                                    slot: $connectedSlot,
                                    labelDisabled: useSSIDAsMenuBarLabel,
                                    onChange: { onSlotChanged(); IconPreferences.save(connectedSlot, for: .connected) },
                                    onReset: {
                                        connectedSlot = IconPreferences.defaultSlot(for: .connected)
                                        onSlotChanged(); IconPreferences.save(connectedSlot, for: .connected)
                                    })
                        Divider().padding(.leading, 14)
                        IconSlotRow(label: "Blocked",
                                    statusDescription: "Connected, but no internet (e.g. captive network)",
                                    defaultSlot: IconPreferences.defaultSlot(for: .blocked),
                                    slot: $blockedSlot,
                                    labelDisabled: useSSIDAsMenuBarLabel,
                                    onChange: { onSlotChanged(); IconPreferences.save(blockedSlot, for: .blocked) },
                                    onReset: {
                                        blockedSlot = IconPreferences.defaultSlot(for: .blocked)
                                        onSlotChanged(); IconPreferences.save(blockedSlot, for: .blocked)
                                    })
                        Divider().padding(.leading, 14)
                        IconSlotRow(label: "No Network",
                                    statusDescription: "No Wi-Fi or Ethernet connection detected",
                                    defaultSlot: IconPreferences.defaultSlot(for: .noNetwork),
                                    slot: $noNetworkSlot,
                                    onChange: { onSlotChanged(); IconPreferences.save(noNetworkSlot, for: .noNetwork) },
                                    onReset: {
                                        noNetworkSlot = IconPreferences.defaultSlot(for: .noNetwork)
                                        onSlotChanged(); IconPreferences.save(noNetworkSlot, for: .noNetwork)
                                    })
                        Divider().padding(.leading, 14)

                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                Button { showSymbolBrowser = true } label: {
                                    Label("Icon Sets", systemImage: "square.grid.2x2")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }.buttonStyle(.plain)

                                if showSetSavedConfirmation {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
                                        Text("Icon Set Saved").font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
                                    }
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal:   .move(edge: .leading).combined(with: .opacity)))
                                }

                                if shouldShowSaveButton {
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            showSaveSetPanel.toggle()
                                            if !showSaveSetPanel { saveSetName = "" }
                                        }
                                    } label: {
                                        Label("Save as new set", systemImage: "bookmark.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(showSaveSetPanel ? Color.accentColor : .secondary)
                                    }.buttonStyle(.plain).transition(.opacity.combined(with: .scale))
                                }

                                Spacer()

                                Button {
                                    withAnimation {
                                        IconPreferences.resetAll()
                                        connectedSlot = IconPreferences.slot(for: .connected)
                                        blockedSlot   = IconPreferences.slot(for: .blocked)
                                        noNetworkSlot = IconPreferences.slot(for: .noNetwork)
                                        showSaveSetPanel = false; saveSetName = ""
                                        suppressSaveButton = false; showSetSavedConfirmation = false
                                    }
                                } label: {
                                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }.buttonStyle(.plain)
                            }
                            .animation(.easeInOut(duration: 0.25), value: isModifiedFromDefault)
                            .animation(.easeInOut(duration: 0.25), value: suppressSaveButton)
                            .animation(.easeInOut(duration: 0.25), value: showSetSavedConfirmation)
                            .padding(.horizontal, 14).padding(.vertical, 10)

                            if showSaveSetPanel {
                                Divider().padding(.horizontal, 14)
                                HStack(spacing: 8) {
                                    TextField("Name this set…", text: $saveSetName)
                                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                                    Button("Save") { saveCurrentSet() }
                                        .buttonStyle(.borderedProminent).controlSize(.small)
                                        .disabled(saveSetName.trimmingCharacters(in: .whitespaces).isEmpty)
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            showSaveSetPanel = false; saveSetName = ""
                                        }
                                    } label: {
                                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                                    }.buttonStyle(.bordered).controlSize(.small)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Keyboard Shortcuts Tab

        private var keyboardShortcutsTab: some View {
            ScrollView {
                VStack(spacing: 16) {

                    SettingsSection(title: "Keyboard Shortcuts") {
                        ShortcutRecorderRow(
                            title: "Toggle Wi-Fi On / Off",
                            excludedKey: KeyboardShortcutManager.wifiToggleKey,
                            shortcut: $wifiToggleShortcut,
                            onCommit: { sc in
                                KeyboardShortcutManager.shared.save(sc, for: KeyboardShortcutManager.wifiToggleKey)
                            }
                        )

                        Divider().padding(.leading, 14)

                        ShortcutRecorderRow(
                            title: "Open Wi-Fi Settings",
                            excludedKey: KeyboardShortcutManager.wifiSettingsKey,
                            shortcut: $wifiSettingsShortcut,
                            onCommit: { sc in
                                KeyboardShortcutManager.shared.save(sc, for: KeyboardShortcutManager.wifiSettingsKey)
                            }
                        )

                        Divider().padding(.leading, 14)

                        ShortcutRecorderRow(
                            title: "Open Network Settings",
                            excludedKey: KeyboardShortcutManager.vpnSettingsKey,
                            shortcut: $vpnSettingsShortcut,
                            onCommit: { sc in
                                KeyboardShortcutManager.shared.save(sc, for: KeyboardShortcutManager.vpnSettingsKey)
                            }
                        )
                    }
                    .padding(.horizontal, 0)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Requires at least one modifier key: ⌃, ⌥, ⇧, or ⌘")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Click record, then press your desired key combination.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)

                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.windowBackgroundColor))
        }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable()
                        .frame(width: 64, height: 64)

                    VStack(spacing: 3) {
                        Text(AppInfo.appName)
                            .font(.system(size: 15, weight: .semibold))
                        Text("Version \(AppInfo.marketingVersion) · Build \(AppInfo.buildVersion)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20).padding(.bottom, 16).padding(.horizontal, 20)

                Divider()

                Button {
                    if let url = URL(string: "https://github.com/\(UpdateChecker.repoOwner)/\(UpdateChecker.repoName)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                        Text("View on GitHub").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .background(Color(.quaternarySystemFill).opacity(0.6))
            }
            .background(Color(.quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
            .padding(.horizontal, 40)

            Spacer()

            Divider()
            Text("\(AppInfo.appName) by \(UpdateChecker.repoOwner)  ·  MIT License")
                .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Helpers

    private func formatInterval(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    private func applyInterval() {
        let value = Double(intervalText) ?? 0
        guard value >= 1 else { withAnimation { intervalInvalid = true }; return }
        intervalInvalid = false; interval = value
        UserDefaults.standard.set(value, forKey: "refreshInterval")
        AppState.shared.restart()
        withAnimation { intervalSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { intervalSaved = false } }
    }

    private func applyPingURL() {
        let t = pingURL.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty {
            let ok = URL(string: t).flatMap { $0.scheme.map { ["http", "https"].contains($0) } } ?? false
            if !ok { withAnimation { pingURLInvalid = true }; return }
        }
        pingURLInvalid = false
        t.isEmpty ? UserDefaults.standard.removeObject(forKey: "pingURL")
                  : UserDefaults.standard.set(t, forKey: "pingURL")
        withAnimation { pingURLSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { pingURLSaved = false } }
    }

    private func restoreDefaultPingURL() {
        UserDefaults.standard.removeObject(forKey: "pingURL")
        withAnimation { pingURL = "" }
        withAnimation { pingURLSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { pingURLSaved = false } }
    }

    private func saveCurrentSet() {
        let t = saveSetName.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        userSetsStore.add(UserIconSet.from(name: t, connected: connectedSlot, blocked: blockedSlot, noNetwork: noNetworkSlot))
        withAnimation(.easeInOut(duration: 0.2)) {
            showSaveSetPanel = false; saveSetName = ""
            suppressSaveButton = true; showSetSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.35)) { showSetSavedConfirmation = false }
        }
    }

    // MARK: - SSID feature handlers

    private func handleShowWifiNameInMenuToggle(_ enabled: Bool) {
        if enabled {
            switch SSIDManager.shared.authorizationStatus {
            case .authorizedAlways:
                commitWifiNameInMenu(true)
            case .notDetermined:
                ssidFeaturePendingAuth = .menuItem
                showLocationAlert = true
            default:
                ssidFeaturePendingAuth = .menuItem
                showLocationDeniedAlert = true
            }
        } else {
            commitWifiNameInMenu(false)
        }
    }

    private func handleUseSSIDAsMenuBarLabelToggle(_ enabled: Bool) {
        if enabled {
            switch SSIDManager.shared.authorizationStatus {
            case .authorizedAlways:
                useSSIDAsMenuBarLabel = false
                showOverrideAlert = true
            case .notDetermined:
                useSSIDAsMenuBarLabel = false
                ssidFeaturePendingAuth = .menuBarLabel
                showLocationAlert = true
            default:
                useSSIDAsMenuBarLabel = false
                ssidFeaturePendingAuth = .menuBarLabel
                showLocationDeniedAlert = true
            }
        } else {
            commitWifiNameAsLabel(false)
        }
    }

    private func commitWifiNameInMenu(_ enabled: Bool) {
        wifiNameInMenuSSID = enabled ? SSIDManager.shared.currentSSID() : nil
        UserDefaults.standard.set(enabled, forKey: "showWifiNameInMenu")
        withAnimation(.easeInOut(duration: 0.2)) {
            showWifiNameInMenu = enabled
        }
        if !enabled && useSSIDAsMenuBarLabel {
            commitWifiNameAsLabel(false)
        }
    }

    private func commitWifiNameAsLabel(_ enabled: Bool) {
        useSSIDAsMenuBarLabel = enabled
        UserDefaults.standard.set(enabled, forKey: "useSSIDAsMenuBarLabel")
        NotificationCenter.default.post(name: .iconPreferencesChanged, object: nil)
    }

    private func checkForUpdates() {
        withAnimation { updateStatus = .checking }
        UpdateChecker.check { result in
            withAnimation {
                switch result {
                case .upToDate:
                    updateStatus = .upToDate
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { updateStatus = .idle } }
                case .updateAvailable(let tag, let page):
                    cachedPageURL = page
                    updateStatus = .available(tag: tag, pageURL: page)
                case .error(let msg):
                    updateStatus = .error(msg)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { updateStatus = .idle } }
                }
            }
        }
    }

    private func openPageURL() {
        guard let url = cachedPageURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Tab Bar Button

private struct TabBarButton: View {
    let title: String
    let systemImage: String
    let tag: Int
    @Binding var selected: Int

    private var isSelected: Bool { selected == tag }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selected = tag }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Click Actions Block

private struct ClickActionsBlock: View {

    let leftLabel:    String
    let rightLabel:   String
    @Binding var leftAction:  String
    @Binding var rightAction: String
    @Binding var isSwapped:   Bool
    let leftOptions:  [(label: String, tag: String)]
    let rightOptions: [(label: String, tag: String)]
    let enabled:      Bool
    let onLeftChanged:  () -> Void
    let onRightChanged: () -> Void
    let onSwapChanged:  () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(leftLabel).font(.system(size: 12)).foregroundStyle(.primary)
                    Spacer()
                    Picker("", selection: $leftAction) {
                        ForEach(leftOptions, id: \.tag) { Text($0.label).tag($0.tag) }
                    }
                    .pickerStyle(.menu).labelsHidden().frame(width: 185)
                    .disabled(!enabled).onChange(of: leftAction) { _, _ in onLeftChanged() }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)

                Divider()

                HStack(spacing: 10) {
                    Text(rightLabel).font(.system(size: 12)).foregroundStyle(.primary)
                    Spacer()
                    Picker("", selection: $rightAction) {
                        ForEach(rightOptions, id: \.tag) { Text($0.label).tag($0.tag) }
                    }
                    .pickerStyle(.menu).labelsHidden().frame(width: 185)
                    .disabled(!enabled).onChange(of: rightAction) { _, _ in onRightChanged() }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isSwapped.toggle() }
                onSwapChanged()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain).frame(width: 36).foregroundStyle(Color.secondary).disabled(!enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(.windowBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(.leading, 56).padding(.trailing, 14).padding(.bottom, 12)
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.18), value: enabled)
    }
}

// MARK: - Icon Slot Row

private struct IconSlotRow: View {
    let label: String
    let statusDescription: String
    let defaultSlot: IconPreferences.Slot
    @Binding var slot: IconPreferences.Slot
    var labelDisabled: Bool = false
    let onChange: () -> Void
    let onReset:  () -> Void

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(slot.color) }, set: { slot.color = NSColor($0); onChange() })
    }
    private var symbolIsValid: Bool {
        NSImage(systemSymbolName: slot.symbolName, accessibilityDescription: nil) != nil
    }
    private var isSlotModified: Bool {
        guard let dc = defaultSlot.color.usingColorSpace(.sRGB),
              let sc = slot.color.usingColorSpace(.sRGB) else { return true }
        let colorChanged = abs(dc.redComponent - sc.redComponent) > 0.001 ||
                           abs(dc.greenComponent - sc.greenComponent) > 0.001 ||
                           abs(dc.blueComponent  - sc.blueComponent)  > 0.001
        return slot.symbolName != defaultSlot.symbolName ||
               slot.menuLabel  != defaultSlot.menuLabel  ||
               slot.menuLabelEnabled != defaultSlot.menuLabelEnabled || colorChanged
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .center, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(slot.color).opacity(0.15)).frame(width: 44, height: 44)
                    if symbolIsValid {
                        Image(systemName: slot.symbolName)
                            .font(.system(size: 19, weight: .medium)).foregroundStyle(Color(slot.color))
                    } else {
                        Image(systemName: "questionmark")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Text(label).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center)
                Text(statusDescription).font(.system(size: 10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 110)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SF Symbol Name").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    TextField("e.g. wifi", text: Binding(
                        get: { slot.symbolName }, set: { slot.symbolName = $0; onChange() }
                    )).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                    if !symbolIsValid && !slot.symbolName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                            Text("Symbol not found — check SF Symbols").font(.system(size: 10))
                        }.foregroundStyle(.red)
                    }
                }
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            if labelDisabled {
                                Text("Menu Bar Label")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.primary.opacity(0.28))
                            } else {
                                Image(systemName: slot.menuLabelEnabled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(slot.menuLabelEnabled ? Color.accentColor : Color.primary.opacity(0.28))
                                    .animation(.easeInOut(duration: 0.15), value: slot.menuLabelEnabled)
                                Text("Menu Bar Label")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(slot.menuLabelEnabled ? Color.accentColor : Color.primary.opacity(0.28))
                                    .animation(.easeInOut(duration: 0.15), value: slot.menuLabelEnabled)
                            }
                        }
                        if labelDisabled {
                            Text("Wi-Fi Name")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(.quaternarySystemFill))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                                        )
                                )
                        } else {
                            TextField("optional label", text: Binding(
                                get: { slot.menuLabel },
                                set: {
                                    slot.menuLabel = String($0.prefix(15))
                                    let enabled = !slot.menuLabel.isEmpty
                                    if slot.menuLabelEnabled != enabled { slot.menuLabelEnabled = enabled }
                                    onChange()
                                }
                            ))
                            .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(height: 28)
                        }
                    }.frame(maxWidth: .infinity)

                    VStack(alignment: .center, spacing: 4) {
                        Text("Color").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.28))
                        ColorPicker("", selection: colorBinding, supportsOpacity: false)
                            .labelsHidden().frame(width: 36, height: 28)
                    }.frame(width: 44)

                    VStack(alignment: .center, spacing: 4) {
                        Text("Reset").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSlotModified ? Color.primary.opacity(0.28) : Color.primary.opacity(0.18))
                            .animation(.easeInOut(duration: 0.15), value: isSlotModified)
                        Button { withAnimation(.easeInOut(duration: 0.15)) { onReset() } } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 28, height: 28).contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .background(Circle().fill(Color.primary.opacity(isSlotModified ? 0.08 : 0.04)).frame(width: 28, height: 28))
                        .foregroundStyle(isSlotModified ? Color.primary.opacity(0.75) : Color.primary.opacity(0.18))
                        .disabled(!isSlotModified)
                        .animation(.easeInOut(duration: 0.15), value: isSlotModified)
                    }.frame(width: 44)
                }
            }.frame(maxWidth: .infinity)
        }
        .padding(16)
    }
}

// MARK: - Shortcut Recorder Row

private struct ShortcutRecorderRow: View {
    let title:      String
    let excludedKey: String
    @Binding var shortcut: KeyboardShortcut?
    let onCommit: (KeyboardShortcut?) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            ShortcutRecorderField(excludedKey: excludedKey, shortcut: $shortcut, onCommit: onCommit)
                .frame(width: 200, height: 28)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {

    let excludedKey: String
    @Binding var shortcut: KeyboardShortcut?
    let onCommit: (KeyboardShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let v = ShortcutRecorderNSView()
        v.onCommit = { [weak v] sc in
            DispatchQueue.main.async {
                self.shortcut = sc
                self.onCommit(sc)
                v?.window?.makeFirstResponder(nil)
            }
        }

        let excluded = excludedKey
        v.conflictChecker = { candidate in
            let allSlots: [(key: String, label: String)] = [
                (KeyboardShortcutManager.wifiToggleKey,   "Toggle Wi-Fi On / Off"),
                (KeyboardShortcutManager.wifiSettingsKey, "Open Wi-Fi Settings"),
                (KeyboardShortcutManager.vpnSettingsKey,  "Open Network Settings"),
            ]
            for slot in allSlots {
                guard slot.key != excluded else { continue }
                if let existing = KeyboardShortcutManager.shared.shortcut(for: slot.key),
                   existing.keyCode == candidate.keyCode,
                   existing.modifiers == candidate.modifiers {
                    return slot.label
                }
            }
            return nil
        }
        return v
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        if nsView.shortcut != shortcut {
            nsView.shortcut = shortcut
        }
    }
}

// MARK: - ShortcutRecorderNSView

private extension Notification.Name {

    static let shortcutRecorderDidBeginRecording = Notification.Name("shortcutRecorderDidBeginRecording")
}

final class ShortcutRecorderNSView: NSView {

    var onCommit: ((KeyboardShortcut?) -> Void)?

    var conflictChecker: ((KeyboardShortcut) -> String?)?

    var shortcut: KeyboardShortcut? { didSet { needsDisplay = true } }

    private(set) var isRecording: Bool = false {
        didSet { needsDisplay = true }
    }

    private var liveModifiers: NSEvent.ModifierFlags = [] {
        didSet { needsDisplay = true }
    }

    private var localMonitor: Any?
    private var flagsMonitor:  Any?

    private let cornerRadius: CGFloat = 8
    private let hPad:         CGFloat = 10
    private let fieldHeight:  CGFloat = 28
    private let minWidth:     CGFloat = 140

    override var intrinsicContentSize: NSSize { NSSize(width: minWidth, height: fieldHeight) }
    override var acceptsFirstResponder: Bool  { true }
    override var canBecomeKeyView:      Bool  { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(otherRecorderBegan(_:)),
            name: .shortcutRecorderDidBeginRecording,
            object: nil
        )
    }
    required init?(coder: NSCoder) { fatalError() }

    private func startRecording() {
        guard !isRecording else { return }
        
        NotificationCenter.default.post(name: .shortcutRecorderDidBeginRecording, object: self)
        
        KeyboardShortcutManager.shared.suspend()
        liveModifiers = []
        isRecording = true
        window?.makeFirstResponder(self)
        installLocalMonitor()
        installFlagsMonitor()
    }

    private func stopRecording(commit: KeyboardShortcut?) {
        guard isRecording else { return }
        removeLocalMonitor()
        removeFlagsMonitor()
        liveModifiers = []
        KeyboardShortcutManager.shared.resume()
        isRecording = false

        guard let sc = commit else { onCommit?(nil); return }

        if let conflictLabel = conflictChecker?(sc) {
            DispatchQueue.main.async { [weak self] in
                let alert = NSAlert()
                alert.messageText = "Shortcut Already in Use"
                alert.informativeText = "\"\(sc.displayString)\" is already assigned to \"\(conflictLabel)\". \n\nPlease choose a different combination."
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .warning

                if let window = self?.window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
            return
        }

        onCommit?(sc)
    }

    private func cancelRecording() {
        guard isRecording else { return }
        removeLocalMonitor()
        removeFlagsMonitor()
        liveModifiers = []
        KeyboardShortcutManager.shared.resume()
        isRecording = false
    }

    @objc private func otherRecorderBegan(_ note: Notification) {
        
        guard note.object as? ShortcutRecorderNSView !== self else { return }
        cancelRecording()
    }

    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.handleKeyEvent(event)
            return nil
        }
    }

    private func removeLocalMonitor() {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        localMonitor = nil
    }

    private func installFlagsMonitor() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.liveModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            return event
        }
    }

    private func removeFlagsMonitor() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        flagsMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == 53 { cancelRecording(); return }
        if event.keyCode == 51 || event.keyCode == 117 { stopRecording(commit: nil); return }

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        let modifierOnlyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierOnlyCodes.contains(event.keyCode) { return }

        guard !mods.isEmpty else { return }

        let sc = KeyboardShortcut(keyCode: event.keyCode, modifiers: mods.rawValue)
        stopRecording(commit: sc)
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        if shortcut != nil && !isRecording {
            let clearRect = NSRect(x: bounds.width - fieldHeight, y: 0,
                                   width: fieldHeight, height: fieldHeight)
            if clearRect.contains(pt) {
                onCommit?(nil)
                DispatchQueue.main.async { [weak self] in
                    self?.shortcut = nil
                }
                return
            }
        }

        if isRecording {
            cancelRecording()
        } else {
            startRecording()
        }
    }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let rect = NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: fieldHeight - 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

            if isRecording {
                NSColor.systemRed.withAlphaComponent(0.04).setFill()
                path.fill()
                NSColor.systemRed.withAlphaComponent(0.35).setStroke()
                path.lineWidth = 1.0
                path.stroke()
                drawRecordingState(in: rect)
            } else if shortcut != nil {
                drawSetState(in: rect)
            } else {
                NSColor.controlBackgroundColor.setFill()
                path.fill()
                NSColor.separatorColor.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                drawEmptyState(in: rect)
            }
        }

        private func drawEmptyState(in rect: NSRect) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let str = NSAttributedString(string: "Click to record", attributes: attrs)
            let sz  = str.size()
            str.draw(at: NSPoint(x: (rect.width - sz.width) / 2,
                                 y: (fieldHeight - sz.height) / 2))
        }

        private func drawRecordingState(in rect: NSRect) {
            let dotD: CGFloat = 7
            let dotX = hPad + 2
            let dotY = (fieldHeight - dotD) / 2
            let dotPath = NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotD, height: dotD))
            NSColor.systemRed.withAlphaComponent(0.95).setFill()
            dotPath.fill()

            let escFont  = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
            let escText  = "esc"
            let escAttrs: [NSAttributedString.Key: Any] = [.font: escFont,
                                                            .foregroundColor: NSColor.secondaryLabelColor]
            let escTextSz  = (escText as NSString).size(withAttributes: escAttrs)
            let escCapH: CGFloat = 16
            let escCapW          = escTextSz.width + 10
            let escCapX          = rect.width - hPad - escCapW
            let escCapY          = (fieldHeight - escCapH) / 2
            let escCapRect       = NSRect(x: escCapX, y: escCapY, width: escCapW, height: escCapH)
            let escPath          = NSBezierPath(roundedRect: escCapRect, xRadius: 4, yRadius: 4)
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            escPath.fill()
            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            escPath.lineWidth = 0.5
            escPath.stroke()
            NSAttributedString(string: escText, attributes: escAttrs)
                .draw(at: NSPoint(x: escCapX + (escCapW - escTextSz.width) / 2,
                                  y: escCapY + (escCapH - escTextSz.height) / 2))

            let leftEdge  = dotX + dotD + 8
            let rightEdge = escCapX - 6

            if liveModifiers.isEmpty {
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.systemRed.withAlphaComponent(0.9)
                ]
                let label   = NSAttributedString(string: "Recording…", attributes: labelAttrs)
                let labelSz = label.size()
                let labelX  = leftEdge + ((rightEdge - leftEdge) - labelSz.width) / 2
                label.draw(at: NSPoint(x: max(leftEdge, labelX),
                                       y: (fieldHeight - labelSz.height) / 2))
            } else {
                drawLiveModifiers(leftEdge: leftEdge, rightEdge: rightEdge)
            }
        }

    private func drawLiveModifiers(leftEdge: CGFloat, rightEdge: CGFloat) {
        var parts: [String] = []
        if liveModifiers.contains(.control) { parts.append("⌃") }
        if liveModifiers.contains(.option)  { parts.append("⌥") }
        if liveModifiers.contains(.shift)   { parts.append("⇧") }
        if liveModifiers.contains(.command) { parts.append("⌘") }
        guard !parts.isEmpty else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        
        let textColor = NSColor.labelColor.withAlphaComponent(0.95)

        let displayString = parts.joined(separator: " + ")

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: -0.3
        ]

        let str = NSAttributedString(string: displayString, attributes: attrs)
        let textSize = str.size()

        let padX: CGFloat = 10
        let padY: CGFloat = 4

        let outerPadY: CGFloat = 6

        let totalW = textSize.width + padX * 2
        let totalH = textSize.height + padY * 2

        let availW = rightEdge - leftEdge
        let originX = leftEdge + (availW - totalW) / 2

        let availableHeight = fieldHeight - outerPadY * 2
        let originY = outerPadY + (availableHeight - totalH) / 2

        let bgRect = NSRect(x: originX, y: originY, width: totalW, height: totalH)

        let bgColor     = NSColor.labelColor.withAlphaComponent(0.08)
        let borderColor = NSColor.labelColor.withAlphaComponent(0.25)
        
        let path = NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8)
        bgColor.setFill()
        path.fill()

        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let textX = originX + (totalW - textSize.width) / 2
        let textY = originY + (totalH - textSize.height) / 2

        str.draw(at: NSPoint(x: textX, y: textY))
    }

        private func drawSetState(in rect: NSRect) {
            guard let sc = shortcut else { return }

            let xAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .light),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let xStr = NSAttributedString(string: "×", attributes: xAttrs)
            let xSz  = xStr.size()
            let xX   = rect.width - hPad - xSz.width
            xStr.draw(at: NSPoint(x: xX, y: (fieldHeight - xSz.height) / 2))

            drawKeyCaps(for: sc, rightEdge: xX - 8, in: rect)
        }

    private func drawKeyCaps(for sc: KeyboardShortcut, rightEdge: CGFloat, in rect: NSRect) {
        var parts: [String] = []
        let flags = sc.modifierFlags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(KeyboardShortcut.keyCodeToString(sc.keyCode))

        let capFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        let capPad: CGFloat = 4
        let capR:   CGFloat = 6

        let sampleH = ("W" as NSString).size(withAttributes: [.font: capFont]).height
        let capH    = ceil(sampleH + capPad * 2)
        let minCapW = capH

        let capFill   = NSColor.labelColor.withAlphaComponent(0.08)
        let capBorder = NSColor.labelColor.withAlphaComponent(0.25)

        let plusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.5)
        ]
        let plusStr  = NSAttributedString(string: "+", attributes: plusAttrs)
        let plusSz   = plusStr.size()
        let plusGap: CGFloat = 3

        var widths: [CGFloat] = []
        for part in parts {
            let textW = (part as NSString).size(withAttributes: [.font: capFont]).width
            widths.append(max(minCapW, ceil(textW + capPad * 2)))
        }

        var totalWidth: CGFloat = widths.reduce(0, +)
        if parts.count > 1 {
            totalWidth += CGFloat(parts.count - 1) * (plusGap * 2 + ceil(plusSz.width))
        }

        var x    = rightEdge - totalWidth
        let capY = (fieldHeight - capH) / 2

        for (i, part) in parts.enumerated() {
            let w       = widths[i]
            let capRect = NSRect(x: x, y: capY, width: w, height: capH)
            let capPath = NSBezierPath(roundedRect: capRect, xRadius: capR, yRadius: capR)

            capFill.setFill()
            capPath.fill()

            capBorder.setStroke()
            capPath.lineWidth = 1
            capPath.stroke()

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: capFont,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.95)
            ]
            let str = NSAttributedString(string: part, attributes: textAttrs)
            let sz  = str.size()

            str.draw(at: NSPoint(
                x: x + (w - sz.width) / 2,
                y: capY + (capH - sz.height) / 2
            ))

            x += w

            if i < parts.count - 1 {
                x += plusGap
                plusStr.draw(at: NSPoint(
                    x: x,
                    y: capY + (capH - plusSz.height) / 2
                ))
                x += ceil(plusSz.width) + plusGap
            }
        }
    }

        deinit {
            removeLocalMonitor()
            removeFlagsMonitor()
            NotificationCenter.default.removeObserver(self)
        }
    }

// MARK: - IP Hide Block

private struct IPHideBlock: View {

    @Binding var hideIPv4: Bool
    @Binding var hideIPv6: Bool
    let onIPv4Changed: () -> Void
    let onIPv6Changed: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("IPv4").font(.system(size: 12)).foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $hideIPv4).labelsHidden()
                    .onChange(of: hideIPv4) { _, _ in onIPv4Changed() }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            Divider()

            HStack(spacing: 10) {
                Text("IPv6").font(.system(size: 12)).foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $hideIPv6).labelsHidden()
                    .onChange(of: hideIPv6) { _, _ in onIPv6Changed() }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
        .background(Color(.windowBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(.leading, 56).padding(.trailing, 14).padding(.bottom, 12)
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    let trailingHeaderView: AnyView?
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.trailingHeaderView = nil; self.content = content()
    }
    init<T: View>(title: String, trailing: () -> T, @ViewBuilder content: () -> Content) {
        self.title = title; self.trailingHeaderView = AnyView(trailing()); self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 4)
                if let trailing = trailingHeaderView { Spacer(); trailing.padding(.horizontal, 4) }
            }
            VStack(spacing: 0) { content }
                .background(Color(.quaternarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow<Control: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(iconColor).frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

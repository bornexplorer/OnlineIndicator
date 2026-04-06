import SwiftUI
import AppKit

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

    private let leftClickOptions: [(label: String, tag: String)] = [
        ("Open Wi-Fi Settings",   "wifi"),
        ("Check Connection Now",  "checkNow"),
        ("Toggle Wi-Fi On / Off", "wifiToggle")
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
                TabBarButton(title: "About",      systemImage: "info.circle.fill", tag: 2, selected: $selectedTab)
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
                        HStack(spacing: 8) {
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

                    if intervalInvalid {
                        HStack(spacing: 0) {
                            Spacer().frame(width: 56)
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                                Text("Minimum interval is 1 second").font(.system(size: 10))
                            }
                            .foregroundStyle(.red).transition(.opacity.combined(with: .move(edge: .top)))
                            Spacer()
                        }
                        .padding(.bottom, 4).animation(.easeInOut(duration: 0.18), value: intervalInvalid)
                    }

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
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
                    }
                    .padding(.vertical, 10)

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

                SettingsSection(title: "Menu Bar") {
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
                        onLeftChanged:  { UserDefaults.standard.set(leftClickAction,       forKey: "leftClickAction") },
                        onRightChanged: { UserDefaults.standard.set(rightClickAction,      forKey: "rightClickAction") },
                        onSwapChanged:  { UserDefaults.standard.set(leftRightClickSwapped, forKey: "leftRightClickSwapped") }
                    )

                    Divider().padding(.leading, 56)

                    SettingsRow(icon: "eye.slash", iconColor: .gray,
                                title: "Hide IPv4",
                                subtitle: "Remove IPv4 address from the menu") {
                        Toggle("", isOn: $hideIPv4).labelsHidden()
                            .onChange(of: hideIPv4) { _, v in UserDefaults.standard.set(v, forKey: "hideIPv4") }
                    }

                    Divider().padding(.leading, 56)

                    SettingsRow(icon: "eye.slash", iconColor: .gray,
                                title: "Hide IPv6",
                                subtitle: "Remove IPv6 address from the menu") {
                        Toggle("", isOn: $hideIPv6).labelsHidden()
                            .onChange(of: hideIPv6) { _, v in UserDefaults.standard.set(v, forKey: "hideIPv6") }
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.windowBackgroundColor))
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
                        IconSlotRow(label: "Connected",
                                    statusDescription: "Internet access is available and this Mac is online",
                                    defaultSlot: IconPreferences.defaultSlot(for: .connected),
                                    slot: $connectedSlot,
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
                            Image(systemName: slot.menuLabelEnabled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(slot.menuLabelEnabled ? Color.accentColor : Color.primary.opacity(0.28))
                                .animation(.easeInOut(duration: 0.15), value: slot.menuLabelEnabled)
                            Text("Menu Bar Label")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(slot.menuLabelEnabled ? Color.accentColor : Color.primary.opacity(0.28))
                                .animation(.easeInOut(duration: 0.15), value: slot.menuLabelEnabled)
                        }
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

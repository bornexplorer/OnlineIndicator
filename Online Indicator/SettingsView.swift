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
    @State private var intervalInvalid  = false
    @State private var pingURL          = ""
    @State private var pingURLSaved     = false
    @State private var pingURLInvalid   = false
    @State private var isLaunchEnabled  = false

    // Click actions — defaults mirror the registered UserDefaults factory defaults
    @State private var leftRightClickEnabled = true
    @State private var leftClickAction       = "wifi"
    @State private var rightClickAction      = "menu"

    enum UpdateStatus: Equatable {
        case idle, checking
        case available(tag: String)
        case upToDate
        case error(String)
    }
    @State private var updateStatus: UpdateStatus = .idle
    @State private var cachedUpdateURL: URL?

    @State private var connectedSlot     = IconPreferences.slot(for: .connected)
    @State private var blockedSlot       = IconPreferences.slot(for: .blocked)
    @State private var noNetworkSlot     = IconPreferences.slot(for: .noNetwork)
    @State private var showSymbolBrowser = false
    @State private var showCopiedToast   = false
    @State private var copiedSymbolName  = ""

    @StateObject private var userSetsStore      = UserIconSetsStore()
    @State private var showSaveSetPanel         = false
    @State private var saveSetName              = ""
    @State private var suppressSaveButton       = false
    @State private var showSetSavedConfirmation = false

    // MARK: - Click action option definitions

    private let leftClickOptions: [(label: String, tag: String)] = [
        ("Open Wi-Fi Settings",          "wifi"),
        ("Check Connection Now",         "checkNow"),
        ("Online Indicator Settings",    "settings"),
        ("Online Indicator Menu",        "menu")
    ]

    private let rightClickOptions: [(label: String, tag: String)] = [
        ("Online Indicator Settings",    "settings"),
        ("Online Indicator Menu",        "menu")
    ]

    // MARK: - Modified-from-defaults check

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
        isModifiedFromDefault &&
        !suppressSaveButton &&
        !showSetSavedConfirmation &&
        !currentSlotsMatchAnySavedSet
    }

    private func onSlotChanged() {
        if suppressSaveButton && !currentSlotsMatchAnySavedSet {
            withAnimation(.easeInOut(duration: 0.2)) {
                suppressSaveButton       = false
                showSetSavedConfirmation = false
            }
        }
    }

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
            SymbolBrowserView(
                store: userSetsStore,
                onSelect: { connected, blocked, noNetwork in
                    connectedSlot  = connected
                    blockedSlot    = blocked
                    noNetworkSlot  = noNetwork
                    IconPreferences.save(connected,  for: .connected)
                    IconPreferences.save(blocked,    for: .blocked)
                    IconPreferences.save(noNetwork,  for: .noNetwork)
                    suppressSaveButton       = true
                    showSetSavedConfirmation = false
                    showSaveSetPanel         = false
                    saveSetName              = ""
                }
            )
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
            isLaunchEnabled       = LoginItemManager.shared.isEnabled()
            intervalText          = formatInterval(interval)
            pingURL               = UserDefaults.standard.string(forKey: "pingURL") ?? ""
            connectedSlot         = IconPreferences.slot(for: .connected)
            blockedSlot           = IconPreferences.slot(for: .blocked)
            noNetworkSlot         = IconPreferences.slot(for: .noNetwork)
            leftRightClickEnabled = UserDefaults.standard.bool(forKey: "leftRightClickEnabled")
            leftClickAction       = UserDefaults.standard.string(forKey: "leftClickAction")  ?? "wifi"
            rightClickAction      = UserDefaults.standard.string(forKey: "rightClickAction") ?? "menu"
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidBecomeKey)) { _ in
            isLaunchEnabled       = LoginItemManager.shared.isEnabled()
            connectedSlot         = IconPreferences.slot(for: .connected)
            blockedSlot           = IconPreferences.slot(for: .blocked)
            noNetworkSlot         = IconPreferences.slot(for: .noNetwork)
            leftRightClickEnabled = UserDefaults.standard.bool(forKey: "leftRightClickEnabled")
            leftClickAction       = UserDefaults.standard.string(forKey: "leftClickAction")  ?? "wifi"
            rightClickAction      = UserDefaults.standard.string(forKey: "rightClickAction") ?? "menu"
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
                        subtitle: "Opens automatically when your Mac starts up"
                    ) {
                        Toggle("", isOn: $isLaunchEnabled)
                            .labelsHidden()
                            .onChange(of: isLaunchEnabled) { _, newValue in
                                LoginItemManager.shared.setEnabled(newValue)
                            }
                    }

                    Divider().padding(.leading, 56)

                    // MARK: Click Actions

                    SettingsRow(
                        icon: "cursorarrow.rays",
                        iconColor: .yellow,
                        title: "Click Actions",
                        subtitle: "Assign actions to left and right click"
                    ) {
                        Toggle("", isOn: $leftRightClickEnabled)
                            .labelsHidden()
                            .onChange(of: leftRightClickEnabled) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "leftRightClickEnabled")
                            }
                    }

                    ClickActionRow(
                        label: "Left click",
                        selection: $leftClickAction,
                        options: leftClickOptions,
                        enabled: leftRightClickEnabled
                    ) {
                        UserDefaults.standard.set(leftClickAction, forKey: "leftClickAction")
                    }

                    Divider().padding(.leading, 56)

                    ClickActionRow(
                        label: "Right click",
                        selection: $rightClickAction,
                        options: rightClickOptions,
                        enabled: leftRightClickEnabled
                    ) {
                        UserDefaults.standard.set(rightClickAction, forKey: "rightClickAction")
                    }

                    Divider().padding(.leading, 56)

                    SettingsRow(
                        icon: "arrow.down.circle.fill",
                        iconColor: .blue,
                        title: "Check for Updates",
                        subtitle: "Version \(AppInfo.marketingVersion) (Build \(AppInfo.buildVersion))"
                    ) {
                        HStack(spacing: 8) {
                            switch updateStatus {
                            case .idle:
                                Button("Check") { checkForUpdates() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .transition(.opacity.combined(with: .scale))
                            case .checking:
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.8)
                                    Text("Checking…")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .transition(.opacity)
                            case .upToDate:
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Up to date")
                                        .foregroundStyle(.green)
                                }
                                .font(.system(size: 12))
                                .transition(.opacity.combined(with: .scale))
                            case .available(let tag):
                                Button("Update to \(tag)") { openLatestRelease() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .transition(.opacity.combined(with: .scale))
                            case .error(let msg):
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text(msg)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 11))
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: updateStatus)
                    }
                }

                SettingsSection(title: "Monitoring") {
                    SettingsRow(
                        icon: "clock.fill",
                        iconColor: .orange,
                        title: "Check Interval",
                        subtitle: "How often the app checks if you're connected"
                    ) {
                        HStack(spacing: 8) {
                            TextField("", text: $intervalText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: intervalText) { _, newValue in
                                    // Strip anything that isn't a digit
                                    let digitsOnly = newValue.filter { $0.isNumber }
                                    if digitsOnly != newValue {
                                        intervalText = digitsOnly
                                    }
                                    // Clear the error as soon as the user edits
                                    if intervalInvalid { intervalInvalid = false }
                                }

                            Text("sec")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))

                            if intervalSaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 16))
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Button("Apply") { applyInterval() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .animation(.easeInOut(duration: 0.18), value: intervalSaved)
                    }

                    // Inline error shown when value is below 1 second
                    if intervalInvalid {
                        HStack(spacing: 0) {
                            Spacer().frame(width: 56)
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                Text("Minimum interval is 1 second")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        .animation(.easeInOut(duration: 0.18), value: intervalInvalid)
                    }

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        HStack(spacing: 6) {
                            ForEach([("30s", 30.0), ("1m", 60.0), ("2m", 120.0), ("5m", 300.0)], id: \.1) { lbl, val in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        interval     = val
                                        intervalText = formatInterval(val)
                                        intervalInvalid = false
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
                        subtitle: "The address the app visits to test your connection"
                    ) {
                        EmptyView()
                    }

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                TextField(ConnectivityChecker.defaultURLString, text: $pingURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                    .onChange(of: pingURL) { _, _ in
                                        pingURLInvalid = false
                                    }

                                if pingURLSaved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.system(size: 16))
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Button("Apply") { applyPingURL() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .animation(.easeInOut(duration: 0.18), value: pingURLSaved)

                            if pingURLInvalid {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                    Text("Enter a valid URL")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.trailing, 18)
                        .animation(.easeInOut(duration: 0.18), value: pingURLInvalid)
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
                            statusDescription: "Internet access is available and this Mac is online",
                            defaultSlot: IconPreferences.defaultSlot(for: .connected),
                            slot: $connectedSlot,
                            onChange: {
                                onSlotChanged()
                                IconPreferences.save(connectedSlot, for: .connected)
                            },
                            onReset: {
                                connectedSlot = IconPreferences.defaultSlot(for: .connected)
                                onSlotChanged()
                                IconPreferences.save(connectedSlot, for: .connected)
                            }
                        )

                        Divider().padding(.leading, 14)

                        IconSlotRow(
                            label: "Blocked",
                            statusDescription: "Connected, but no internet (e.g. hotel or airport network)",
                            defaultSlot: IconPreferences.defaultSlot(for: .blocked),
                            slot: $blockedSlot,
                            onChange: {
                                onSlotChanged()
                                IconPreferences.save(blockedSlot, for: .blocked)
                            },
                            onReset: {
                                blockedSlot = IconPreferences.defaultSlot(for: .blocked)
                                onSlotChanged()
                                IconPreferences.save(blockedSlot, for: .blocked)
                            }
                        )

                        Divider().padding(.leading, 14)

                        IconSlotRow(
                            label: "No Network",
                            statusDescription: "No Wi-Fi or cable connection detected",
                            defaultSlot: IconPreferences.defaultSlot(for: .noNetwork),
                            slot: $noNetworkSlot,
                            onChange: {
                                onSlotChanged()
                                IconPreferences.save(noNetworkSlot, for: .noNetwork)
                            },
                            onReset: {
                                noNetworkSlot = IconPreferences.defaultSlot(for: .noNetwork)
                                onSlotChanged()
                                IconPreferences.save(noNetworkSlot, for: .noNetwork)
                            }
                        )

                        Divider().padding(.leading, 14)

                        VStack(spacing: 0) {
                            HStack(spacing: 10) {

                                Button {
                                    showSymbolBrowser = true
                                } label: {
                                    Label("Icon Sets", systemImage: "square.grid.2x2")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)

                                if showSetSavedConfirmation {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.system(size: 11))
                                        Text("Icon Set Saved")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.green)
                                    }
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal:   .move(edge: .leading).combined(with: .opacity)
                                    ))
                                }

                                if shouldShowSaveButton {
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            showSaveSetPanel.toggle()
                                            if !showSaveSetPanel { saveSetName = "" }
                                        }
                                    } label: {
                                        Label("Save edits as new set", systemImage: "bookmark.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(showSaveSetPanel ? Color.accentColor : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.opacity.combined(with: .scale))
                                }

                                Spacer()

                                Button {
                                    withAnimation {
                                        IconPreferences.resetAll()
                                        connectedSlot    = IconPreferences.slot(for: .connected)
                                        blockedSlot      = IconPreferences.slot(for: .blocked)
                                        noNetworkSlot    = IconPreferences.slot(for: .noNetwork)
                                        showSaveSetPanel         = false
                                        saveSetName              = ""
                                        suppressSaveButton       = false
                                        showSetSavedConfirmation = false
                                    }
                                } label: {
                                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .animation(.easeInOut(duration: 0.25), value: isModifiedFromDefault)
                            .animation(.easeInOut(duration: 0.25), value: suppressSaveButton)
                            .animation(.easeInOut(duration: 0.25), value: showSetSavedConfirmation)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)

                            if showSaveSetPanel {
                                Divider().padding(.horizontal, 14)

                                HStack(spacing: 8) {
                                    TextField("Name this set…", text: $saveSetName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))

                                    Button("Save") { saveCurrentSet() }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .disabled(saveSetName.trimmingCharacters(in: .whitespaces).isEmpty)

                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            showSaveSetPanel = false
                                            saveSetName = ""
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
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
        let value = Double(intervalText) ?? 0

        // Enforce minimum of 1 second
        guard value >= 1 else {
            withAnimation { intervalInvalid = true }
            return
        }

        intervalInvalid = false
        interval        = value
        UserDefaults.standard.set(value, forKey: "refreshInterval")
        AppState.shared.restart()

        withAnimation { intervalSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { intervalSaved = false }
        }
    }

    private func applyPingURL() {
        let trimmed = pingURL.trimmingCharacters(in: .whitespaces)

        if !trimmed.isEmpty {
            let isValid = URL(string: trimmed).flatMap { url in
                url.scheme.map { ["http", "https"].contains($0) }
            } ?? false

            if !isValid {
                withAnimation { pingURLInvalid = true }
                return
            }
        }

        pingURLInvalid = false
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

    private func saveCurrentSet() {
        let trimmed = saveSetName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let newSet = UserIconSet.from(
            name: trimmed,
            connected:  connectedSlot,
            blocked:    blockedSlot,
            noNetwork:  noNetworkSlot
        )
        userSetsStore.add(newSet)

        withAnimation(.easeInOut(duration: 0.2)) {
            showSaveSetPanel         = false
            saveSetName              = ""
            suppressSaveButton       = true
            showSetSavedConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.35)) {
                showSetSavedConfirmation = false
            }
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
                case .updateAvailable(let tag, _, let downloadURL, let pageURL):
                    cachedUpdateURL = downloadURL ?? pageURL
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
        guard let url = cachedUpdateURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Click Action Sub-Row

private struct ClickActionRow: View {
    let label: String
    @Binding var selection: String
    let options: [(label: String, tag: String)]
    let enabled: Bool
    let onChanged: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 56)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.tag) { option in
                    Text(option.label).tag(option.tag)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 210)
            .disabled(!enabled)
            .onChange(of: selection) { _, _ in onChanged() }
        }
        .padding(.trailing, 14)
        .padding(.vertical, 8)
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
        Binding(
            get: { Color(slot.color) },
            set: { slot.color = NSColor($0); onChange() }
        )
    }

    private var symbolIsValid: Bool {
        NSImage(systemSymbolName: slot.symbolName, accessibilityDescription: nil) != nil
    }

    private var isSlotModified: Bool {
        guard let dc = defaultSlot.color.usingColorSpace(.sRGB),
              let sc = slot.color.usingColorSpace(.sRGB) else { return true }
        let colorChanged = abs(dc.redComponent   - sc.redComponent)   > 0.001 ||
                           abs(dc.greenComponent - sc.greenComponent) > 0.001 ||
                           abs(dc.blueComponent  - sc.blueComponent)  > 0.001
        return slot.symbolName       != defaultSlot.symbolName ||
               slot.menuLabel        != defaultSlot.menuLabel  ||
               slot.menuLabelEnabled != defaultSlot.menuLabelEnabled ||
               colorChanged
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {

            VStack(alignment: .center, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(slot.color).opacity(0.15))
                        .frame(width: 44, height: 44)
                    if symbolIsValid {
                        Image(systemName: slot.symbolName)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color(slot.color))
                    } else {
                        Image(systemName: "questionmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(statusDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 110)

            VStack(alignment: .leading, spacing: 10) {

                VStack(alignment: .leading, spacing: 4) {
                    Text("SF Symbol Name")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("e.g. wifi", text: Binding(
                        get: { slot.symbolName },
                        set: { slot.symbolName = $0; onChange() }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                    if !symbolIsValid && !slot.symbolName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("Symbol not found — check SF Symbols app")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.red)
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

                        TextField("click to edit", text: Binding(
                            get: { slot.menuLabel },
                            set: {
                                slot.menuLabel = String($0.prefix(15))
                                let enabled = !slot.menuLabel.isEmpty
                                if slot.menuLabelEnabled != enabled {
                                    slot.menuLabelEnabled = enabled
                                }
                                onChange()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(height: 28)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .center, spacing: 4) {
                        Text("Color")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.28))

                        ColorPicker("", selection: colorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 36, height: 28)
                    }
                    .frame(width: 44)

                    VStack(alignment: .center, spacing: 4) {
                        Text("Reset")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSlotModified ? Color.primary.opacity(0.28) : Color.primary.opacity(0.18))
                            .animation(.easeInOut(duration: 0.15), value: isSlotModified)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { onReset() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(isSlotModified ? 0.08 : 0.04))
                                .frame(width: 28, height: 28)
                        )
                        .foregroundStyle(isSlotModified ? Color.primary.opacity(0.75) : Color.primary.opacity(0.18))
                        .disabled(!isSlotModified)
                        .help("Reset this state to default")
                        .animation(.easeInOut(duration: 0.15), value: isSlotModified)
                    }
                    .frame(width: 44)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
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

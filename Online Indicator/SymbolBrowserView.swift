import SwiftUI
import AppKit
import Combine


extension Notification.Name {
    static let symbolCopied = Notification.Name("com.OnlineIndicator.symbolCopied")
}

// MARK: - User Icon Set Model

struct UserIconSet: Codable, Identifiable {
    var id: UUID
    var name: String
    // Connected
    var connectedSymbol: String
    var connectedColorRGBA: [Double]
    var connectedMenuLabel: String
    var connectedMenuLabelEnabled: Bool
    // Blocked
    var blockedSymbol: String
    var blockedColorRGBA: [Double]
    var blockedMenuLabel: String
    var blockedMenuLabelEnabled: Bool
    // No Network
    var noNetworkSymbol: String
    var noNetworkColorRGBA: [Double]
    var noNetworkMenuLabel: String
    var noNetworkMenuLabelEnabled: Bool

    // MARK: - Codable (custom decoder for backward compat with old saves that lack menuLabel fields)

    enum CodingKeys: String, CodingKey {
        case id, name
        case connectedSymbol, connectedColorRGBA, connectedMenuLabel, connectedMenuLabelEnabled
        case blockedSymbol,   blockedColorRGBA,   blockedMenuLabel,   blockedMenuLabelEnabled
        case noNetworkSymbol, noNetworkColorRGBA, noNetworkMenuLabel, noNetworkMenuLabelEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                         = try c.decode(UUID.self,     forKey: .id)
        name                       = try c.decode(String.self,   forKey: .name)
        connectedSymbol            = try c.decode(String.self,   forKey: .connectedSymbol)
        connectedColorRGBA         = try c.decode([Double].self, forKey: .connectedColorRGBA)
        connectedMenuLabel         = try c.decodeIfPresent(String.self, forKey: .connectedMenuLabel) ?? ""
        connectedMenuLabelEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .connectedMenuLabelEnabled) ?? false
        blockedSymbol              = try c.decode(String.self,   forKey: .blockedSymbol)
        blockedColorRGBA           = try c.decode([Double].self, forKey: .blockedColorRGBA)
        blockedMenuLabel           = try c.decodeIfPresent(String.self, forKey: .blockedMenuLabel) ?? ""
        blockedMenuLabelEnabled    = try c.decodeIfPresent(Bool.self,   forKey: .blockedMenuLabelEnabled) ?? false
        noNetworkSymbol            = try c.decode(String.self,   forKey: .noNetworkSymbol)
        noNetworkColorRGBA         = try c.decode([Double].self, forKey: .noNetworkColorRGBA)
        noNetworkMenuLabel         = try c.decodeIfPresent(String.self, forKey: .noNetworkMenuLabel) ?? ""
        noNetworkMenuLabelEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .noNetworkMenuLabelEnabled) ?? false
    }

    // Memberwise init for creating new sets
    init(id: UUID = UUID(), name: String,
         connectedSymbol: String, connectedColorRGBA: [Double], connectedMenuLabel: String, connectedMenuLabelEnabled: Bool,
         blockedSymbol: String, blockedColorRGBA: [Double], blockedMenuLabel: String, blockedMenuLabelEnabled: Bool,
         noNetworkSymbol: String, noNetworkColorRGBA: [Double], noNetworkMenuLabel: String, noNetworkMenuLabelEnabled: Bool) {
        self.id = id
        self.name = name
        self.connectedSymbol = connectedSymbol
        self.connectedColorRGBA = connectedColorRGBA
        self.connectedMenuLabel = connectedMenuLabel
        self.connectedMenuLabelEnabled = connectedMenuLabelEnabled
        self.blockedSymbol = blockedSymbol
        self.blockedColorRGBA = blockedColorRGBA
        self.blockedMenuLabel = blockedMenuLabel
        self.blockedMenuLabelEnabled = blockedMenuLabelEnabled
        self.noNetworkSymbol = noNetworkSymbol
        self.noNetworkColorRGBA = noNetworkColorRGBA
        self.noNetworkMenuLabel = noNetworkMenuLabel
        self.noNetworkMenuLabelEnabled = noNetworkMenuLabelEnabled
    }

    // MARK: - Factory

    static func from(
        name: String,
        connected: IconPreferences.Slot,
        blocked:   IconPreferences.Slot,
        noNetwork: IconPreferences.Slot
    ) -> UserIconSet {
        UserIconSet(
            name: name,
            connectedSymbol:           connected.symbolName,
            connectedColorRGBA:        colorToRGBA(connected.color),
            connectedMenuLabel:        connected.menuLabel,
            connectedMenuLabelEnabled: connected.menuLabelEnabled,
            blockedSymbol:             blocked.symbolName,
            blockedColorRGBA:          colorToRGBA(blocked.color),
            blockedMenuLabel:          blocked.menuLabel,
            blockedMenuLabelEnabled:   blocked.menuLabelEnabled,
            noNetworkSymbol:           noNetwork.symbolName,
            noNetworkColorRGBA:        colorToRGBA(noNetwork.color),
            noNetworkMenuLabel:        noNetwork.menuLabel,
            noNetworkMenuLabelEnabled: noNetwork.menuLabelEnabled
        )
    }

    // MARK: - Convert back to slots (including menuLabel)

    func toSlots() -> (IconPreferences.Slot, IconPreferences.Slot, IconPreferences.Slot) {
        (
            .init(symbolName: connectedSymbol,  color: nsColor(connectedColorRGBA)  ?? .systemGreen,
                  menuLabel: connectedMenuLabel,  menuLabelEnabled: connectedMenuLabelEnabled),
            .init(symbolName: blockedSymbol,    color: nsColor(blockedColorRGBA)    ?? .systemYellow,
                  menuLabel: blockedMenuLabel,    menuLabelEnabled: blockedMenuLabelEnabled),
            .init(symbolName: noNetworkSymbol,  color: nsColor(noNetworkColorRGBA)  ?? .systemRed,
                  menuLabel: noNetworkMenuLabel,  menuLabelEnabled: noNetworkMenuLabelEnabled)
        )
    }

    // MARK: - Helpers

    private static func colorToRGBA(_ color: NSColor) -> [Double] {
        let c = color.usingColorSpace(.sRGB) ?? color
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }

    private func nsColor(_ arr: [Double]) -> NSColor? {
        guard arr.count == 4 else { return nil }
        return NSColor(srgbRed: arr[0], green: arr[1], blue: arr[2], alpha: arr[3])
    }
}

// MARK: - User Icon Sets Store

final class UserIconSetsStore: ObservableObject {
    @Published var sets: [UserIconSet] = []
    private let defaultsKey = "userIconSets_v1"

    init() { load() }

    func add(_ set: UserIconSet) {
        sets.append(set)
        persist()
    }

    func delete(_ set: UserIconSet) {
        sets.removeAll { $0.id == set.id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([UserIconSet].self, from: data)
        else { return }
        sets = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sets) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - Icon Set Model

struct IconSet: Identifiable {
    let id = UUID()
    let name: String
    let connectedSymbol:  String
    let blockedSymbol:    String
    let noNetworkSymbol:  String

    static let connectedColor:  NSColor = .systemGreen
    static let blockedColor:    NSColor = .systemYellow
    static let noNetworkColor:  NSColor = .systemRed

    func toSlots() -> (IconPreferences.Slot, IconPreferences.Slot, IconPreferences.Slot) {
        (
            IconPreferences.Slot(symbolName: connectedSymbol,  color: IconSet.connectedColor,  menuLabel: "", menuLabelEnabled: false),
            IconPreferences.Slot(symbolName: blockedSymbol,    color: IconSet.blockedColor,    menuLabel: "", menuLabelEnabled: false),
            IconPreferences.Slot(symbolName: noNetworkSymbol,  color: IconSet.noNetworkColor,  menuLabel: "", menuLabelEnabled: false)
        )
    }
}

// MARK: - Predefined Sets

private let iconSets: [IconSet] = [
    IconSet(name: "WiFi",        connectedSymbol: "wifi",                                blockedSymbol: "wifi",                               noNetworkSymbol: "wifi.slash"),
    IconSet(name: "Status",      connectedSymbol: "checkmark.circle.fill",               blockedSymbol: "exclamationmark.circle.fill",         noNetworkSymbol: "xmark.circle.fill"),
    IconSet(name: "Shield",      connectedSymbol: "checkmark.shield.fill",               blockedSymbol: "exclamationmark.shield.fill",         noNetworkSymbol: "xmark.shield.fill"),
    IconSet(name: "Lock",        connectedSymbol: "lock.open.fill",                      blockedSymbol: "lock.fill",                          noNetworkSymbol: "lock.slash"),
    IconSet(name: "Bolt",        connectedSymbol: "bolt.fill",                           blockedSymbol: "bolt.fill",                          noNetworkSymbol: "bolt.slash"),
    IconSet(name: "Signals",     connectedSymbol: "antenna.radiowaves.left.and.right",   blockedSymbol: "dot.radiowaves.left.and.right",       noNetworkSymbol: "wifi.slash"),
    IconSet(name: "Globe",       connectedSymbol: "globe",                               blockedSymbol: "globe",                              noNetworkSymbol: "wifi.slash"),
    IconSet(name: "Minimal",     connectedSymbol: "circle.fill",                         blockedSymbol: "circle.fill",                        noNetworkSymbol: "circle.fill"),
    IconSet(name: "Eye",         connectedSymbol: "eye.fill",                            blockedSymbol: "eye.trianglebadge.exclamationmark",   noNetworkSymbol: "eye.slash"),
    IconSet(name: "Cloud",       connectedSymbol: "cloud.fill",                          blockedSymbol: "cloud",                              noNetworkSymbol: "cloud.fill"),
    IconSet(name: "Network",     connectedSymbol: "network",                             blockedSymbol: "network.badge.shield.half.filled",    noNetworkSymbol: "network.slash"),
    IconSet(name: "Heart",       connectedSymbol: "heart.fill",                          blockedSymbol: "heart.fill",                         noNetworkSymbol: "heart.slash"),
    IconSet(name: "Bell",        connectedSymbol: "bell.fill",                           blockedSymbol: "bell.badge",                         noNetworkSymbol: "bell.slash"),
    IconSet(name: "Flag",        connectedSymbol: "flag.fill",                           blockedSymbol: "flag.fill",                          noNetworkSymbol: "flag.slash"),
    IconSet(name: "Power",       connectedSymbol: "power.circle.fill",                   blockedSymbol: "powerplug.fill",                     noNetworkSymbol: "power"),
    IconSet(name: "Hands",       connectedSymbol: "hand.thumbsup.fill",                  blockedSymbol: "hand.raised.fill",                   noNetworkSymbol: "hand.thumbsdown.fill"),
    IconSet(name: "Star",        connectedSymbol: "star.fill",                           blockedSymbol: "star.leadinghalf.filled",             noNetworkSymbol: "star.slash.fill"),
]

// MARK: - Icon Set Browser

struct SymbolBrowserView: View {

    // Store owned by SettingsView; passed in so saves and deletes persist across sheet open/close
    @ObservedObject var store: UserIconSetsStore
    var onSelect: (IconPreferences.Slot, IconPreferences.Slot, IconPreferences.Slot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {

            // ── Fixed header ──────────────────────────────────────────
            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Icon Sets")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Pick a set or customise each state with your own SF Symbols and colours in Appearance.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                }

                Picker("", selection: $selectedTab) {
                    Text("Default Icon Sets").tag(0)
                    Text("My Sets").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(Color(.windowBackgroundColor))

            Divider()

            // ── Scrollable content ────────────────────────────────────
            if selectedTab == 0 {
                defaultSetsScrollView
            } else {
                userSetsScrollView
            }

            // ── Fixed footer ──────────────────────────────────────────
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("Tap a set to apply it to all three states at once")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 360, height: 520)
        .animation(.easeInOut(duration: 0.15), value: selectedTab)
    }

    // MARK: - Default Sets

    private var defaultSetsScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(iconSets.enumerated()), id: \.element.id) { index, set in
                    IconSetRow(set: set) {
                        let (c, b, n) = set.toSlots()
                        onSelect(c, b, n)
                        dismiss()
                    }
                    if index < iconSets.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            )
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - User Sets

    private var userSetsScrollView: some View {
        Group {
            if store.sets.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No saved sets yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Use \"Save edits as new Set\" in the Appearance tab\nto save your current icon configuration.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.sets.enumerated()), id: \.element.id) { index, set in
                            UserSetRow(set: set) {
                                // Tap-to-apply: applies all slots including menuLabel
                                let (c, b, n) = set.toSlots()
                                onSelect(c, b, n)
                                dismiss()
                            } onDelete: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    store.delete(set)
                                }
                            }
                            if index < store.sets.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                    )
                    .padding(16)
                }
                .scrollContentBackground(.hidden)
                .background(Color(.windowBackgroundColor))
            }
        }
    }
}

// MARK: - Default Set Row

private struct IconSetRow: View {

    let set: IconSet
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(set.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 64, alignment: .leading)

                Spacer()

                HStack(spacing: 12) {
                    IconPreviewCell(symbol: set.connectedSymbol,  color: Color(IconSet.connectedColor))
                    IconPreviewCell(symbol: set.blockedSymbol,    color: Color(IconSet.blockedColor))
                    IconPreviewCell(symbol: set.noNetworkSymbol,  color: Color(IconSet.noNetworkColor))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(hovered ? Color.accentColor.opacity(0.07) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - User Set Row (tap anywhere to apply; trash icon to delete immediately)

private struct UserSetRow: View {

    let set: UserIconSet
    let onApply: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    private var connectedColor: Color {
        guard set.connectedColorRGBA.count == 4 else { return .green }
        return Color(NSColor(srgbRed: set.connectedColorRGBA[0], green: set.connectedColorRGBA[1],
                             blue: set.connectedColorRGBA[2], alpha: set.connectedColorRGBA[3]))
    }
    private var blockedColor: Color {
        guard set.blockedColorRGBA.count == 4 else { return .yellow }
        return Color(NSColor(srgbRed: set.blockedColorRGBA[0], green: set.blockedColorRGBA[1],
                             blue: set.blockedColorRGBA[2], alpha: set.blockedColorRGBA[3]))
    }
    private var noNetworkColor: Color {
        guard set.noNetworkColorRGBA.count == 4 else { return .red }
        return Color(NSColor(srgbRed: set.noNetworkColorRGBA[0], green: set.noNetworkColorRGBA[1],
                             blue: set.noNetworkColorRGBA[2], alpha: set.noNetworkColorRGBA[3]))
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(set.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(minWidth: 60, alignment: .leading)

            Spacer()

            HStack(spacing: 10) {
                IconPreviewCell(symbol: set.connectedSymbol,  color: connectedColor)
                IconPreviewCell(symbol: set.blockedSymbol,    color: blockedColor)
                IconPreviewCell(symbol: set.noNetworkSymbol,  color: noNetworkColor)
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete this set")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(hovered ? Color.accentColor.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onApply() }
        .onHover { hovered = $0 }
    }
}

// MARK: - Single icon preview inside a row

private struct IconPreviewCell: View {

    let symbol: String
    let color:  Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 32)

            if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

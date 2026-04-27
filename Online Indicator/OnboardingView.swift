import SwiftUI
import AppKit

struct OnboardingView: View {

    @State private var interval: Double = 5
    @State private var appeared = false
    @State private var launchAtLogin = false
    var onStart: () -> Void

    private let presets: [(label: String, value: Double)] = [
        ("5s", 5), ("10s", 10), ("30s", 30), ("1m", 60)
    ]

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Hero
            VStack(spacing: 16) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .frame(width: 80, height: 80)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.05), value: appeared)

                VStack(spacing: 6) {
                    Text("Online Indicator")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Monitors your connection and displays real time status\nin the menu bar so it is always visible.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: appeared)
            }
            .padding(.top, 36)
            .padding(.bottom, 28)

            Divider()
                .padding(.horizontal, 24)

            // MARK: Interval picker
            VStack(spacing: 12) {
                HStack {
                    Label("Check every", systemImage: "clock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(intervalLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    ForEach(presets, id: \.value) { preset in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                interval = preset.value
                            }
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(interval == preset.value
                                              ? Color.accentColor
                                              : Color.primary.opacity(0.07))
                                )
                                .foregroundStyle(interval == preset.value ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    HStack(spacing: 0) {
                        Button { interval = max(10, interval - 10) } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().frame(height: 16)

                        Button { interval = min(3600, interval + 10) } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.07))
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(0.22), value: appeared)

            Divider()
                .padding(.horizontal, 24)

            // MARK: Status rows
            VStack(spacing: 0) {
                StatusRow(icon: "wifi", color: .green,  label: "Connected to the internet")
                StatusRow(icon: "wifi", color: .yellow, label: "Network present but traffic is blocked")
                StatusRow(icon: "wifi.slash",  color: .red,    label: "No network interface found")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(0.28), value: appeared)

            Divider()
                .padding(.horizontal, 24)

            // MARK: Launch at Login
            HStack {
                Label("Launch at Login", systemImage: "arrow.clockwise.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItemManager.shared.setEnabled(newValue)
                    }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(0.30), value: appeared)

            Divider()
                .padding(.horizontal, 24)

            // MARK: CTA
            Button {
                UserDefaults.standard.set(interval, forKey: "refreshInterval")
                UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")
                onStart()
                NSApp.keyWindow?.close()
            } label: {
                Text("Start Monitoring")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(0.32), value: appeared)
        }
        .frame(width: 420)
        .onAppear { appeared = true }
    }

    private var intervalLabel: String {
        if interval < 60 { return "\(Int(interval))s" }
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

private struct StatusRow: View {
    let icon: String
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

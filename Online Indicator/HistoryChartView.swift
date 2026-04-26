import SwiftUI
import Charts

struct HistoryChartView: View {

    enum TimeRange: String, CaseIterable, Identifiable {
        case oneHour   = "1 Hour"
        case sixHours  = "6 Hours"
        case oneDay    = "24 Hours"
        case sevenDays = "7 Days"
        case allTime   = "All Time"

        var id: String { rawValue }

        var seconds: Int64 {
            switch self {
            case .oneHour:   return 3_600
            case .sixHours:  return 21_600
            case .oneDay:    return 86_400
            case .sevenDays: return 604_800
            case .allTime:   return 0
            }
        }

        var bucketMs: Int64 {
            switch self {
            case .oneHour:   return 60_000
            case .sixHours:  return 300_000
            case .oneDay:    return 300_000
            case .sevenDays: return 300_000
            case .allTime:   return 1_800_000
            }
        }

        var bucketLabel: String {
            switch self {
            case .oneHour:   return "1 min"
            case .sixHours:  return "5 min"
            case .oneDay:    return "5 min"
            case .sevenDays: return "5 min"
            case .allTime:   return "30 min"
            }
        }
    }

    // MARK: - Chart data model

    struct ChartSegment: Identifiable {
        let id = UUID()
        let startTime: Date
        let endTime: Date
        let status: String
    }

    // MARK: - State

    @State private var selectedRange: TimeRange = .oneDay
    @State private var segments: [ChartSegment] = []
    @State private var stats = HistoryStore.Stats(totalRows: 0, connectedRows: 0, avgLatencyMs: 0, outageCount: 0)
    @State private var isLoading = true
    @State private var hoveredSegment: ChartSegment?
    @State private var hoverLocation: CGPoint = .zero

    // MARK: - Colors

    private func color(for status: String) -> Color {
        switch status {
        case "connected": return Color(IconPreferences.slot(for: .connected).color)
        case "blocked":   return Color(IconPreferences.slot(for: .blocked).color)
        case "noNetwork": return Color(IconPreferences.slot(for: .noNetwork).color)
        default:          return .gray
        }
    }

    private func label(for status: String) -> String {
        switch status {
        case "connected": return "Connected"
        case "blocked":   return "Blocked"
        case "noNetwork": return "No Network"
        default:          return status
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Time range picker
            Picker("Range", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .onChange(of: selectedRange) { _, _ in loadData() }

            // Summary stats
            statsRow
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            // Chart or empty state
            if isLoading {
                Spacer(minLength: 0)
                ProgressView("Loading…").controlSize(.small)
                Spacer(minLength: 0)
            } else if segments.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No connection history yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Data will appear after the first connectivity check.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            } else {
                chartView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .onAppear { loadData() }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Uptime",
                value: stats.totalRows > 0
                    ? String(format: "%.1f%%", Double(stats.connectedRows) / Double(stats.totalRows) * 100)
                    : "--",
                icon: "checkmark.shield.fill",
                color: .green
            )
            StatCard(
                title: "Avg Latency",
                value: stats.avgLatencyMs > 0
                    ? String(format: "%.0f ms", stats.avgLatencyMs)
                    : "--",
                icon: "stopwatch",
                color: .orange
            )
            StatCard(
                title: "Outages",
                value: "\(stats.outageCount)",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
        }
    }

    // MARK: - Chart

    private var chartView: some View {
        Chart(segments) { segment in
            BarMark(
                xStart: .value("Start", segment.startTime),
                xEnd:   .value("End",   segment.endTime),
                y:      .value("", 0),
                height: .fixed(28)
            )
            .foregroundStyle(color(for: segment.status))
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel(format: xAxisDateFormat, centered: true)
                    .font(.system(size: 10))
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYAxis(.hidden)
        .chartXScale(domain: xDomain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let location = value.location
                                hoverLocation = location
                                if let segment = segmentAt(location: location, proxy: proxy, geometry: geometry) {
                                    hoveredSegment = segment
                                } else {
                                    hoveredSegment = nil
                                }
                            }
                            .onEnded { _ in
                                hoveredSegment = nil
                            }
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            if let seg = hoveredSegment {
                tooltip(for: seg)
                    .offset(x: clampedTooltipX(), y: -60)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredSegment?.id)
    }

    // MARK: - Tooltip

    private func tooltip(for seg: ChartSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label(for: seg.status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color(for: seg.status))
            Text(timeFormatter.string(from: seg.startTime)
                + " – "
                + timeFormatter.string(from: seg.endTime))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
    }

    private func clampedTooltipX() -> CGFloat {
        // Keep tooltip within the chart area
        let tipW: CGFloat = 200
        let maxX: CGFloat = 380
        return min(max(hoverLocation.x - tipW / 2, 0), maxX - tipW)
    }

    // MARK: - Helpers

    private var xDomain: ClosedRange<Date> {
        let now = Date()
        let start: Date
        if selectedRange == .allTime, let first = segments.first?.startTime {
            start = first
        } else {
            start = now.addingTimeInterval(-Double(selectedRange.seconds))
        }
        return start...now
    }

    private var xAxisDateFormat: Date.FormatStyle {
        switch selectedRange {
        case .oneHour:
            return .dateTime.hour().minute()
        case .sixHours:
            return .dateTime.hour().minute()
        case .oneDay:
            return .dateTime.hour().minute()
        case .sevenDays:
            return .dateTime.month().day().hour()
        case .allTime:
            return .dateTime.month().day()
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        switch selectedRange {
        case .oneHour, .sixHours:
            f.dateFormat = "HH:mm"
        case .oneDay:
            f.dateFormat = "HH:mm"
        case .sevenDays:
            f.dateFormat = "EEE HH:mm"
        case .allTime:
            f.dateFormat = "MMM d, HH:mm"
        }
        return f
    }

    private func segmentAt(location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> ChartSegment? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let origin = geometry[plotFrame].origin
        let relativeX = location.x - origin.x

        guard let xValue = proxy.value(atX: relativeX) as Date? else { return nil }
        return segments.first { xValue >= $0.startTime && xValue < $0.endTime }
    }

    // MARK: - Data loading

    private func loadData() {
        isLoading = true

        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let rangeSeconds = selectedRange.seconds
        let fromMs: Int64 = rangeSeconds > 0
            ? nowMs - (rangeSeconds * 1000)
            : 0
        let toMs = nowMs

        let bucketMs = selectedRange.bucketMs

        HistoryStore.shared.queryBuckets(from: fromMs, to: toMs, bucketMs: bucketMs) { buckets in
            let merged = Self.mergeConsecutive(buckets, bucketMs: bucketMs)
            self.segments = merged

            HistoryStore.shared.queryStats(from: fromMs, to: toMs) { s in
                self.stats = s
                self.isLoading = false
            }
        }
    }

    // Merge consecutive buckets with same status to avoid visual gaps
    static func mergeConsecutive(_ buckets: [HistoryStore.Bucket], bucketMs: Int64) -> [ChartSegment] {
        guard !buckets.isEmpty else { return [] }

        var result: [ChartSegment] = []
        var currentStatus = buckets[0].status
        var currentStart  = buckets[0].timestamp

        for i in 1..<buckets.count {
            let b = buckets[i]
            if b.status == currentStatus {
                // Extend current segment
                continue
            } else {
                result.append(ChartSegment(
                    startTime: Date(timeIntervalSince1970: Double(currentStart) / 1000),
                    endTime:   Date(timeIntervalSince1970: Double(b.timestamp) / 1000),
                    status:    currentStatus
                ))
                currentStatus = b.status
                currentStart  = b.timestamp
            }
        }

        // Final segment
        let endMs: Int64
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let lastBucket = buckets.last!
        // The bucket timestamp + bucketMs covers the period
        endMs = min(lastBucket.timestamp + bucketMs, nowMs)

        result.append(ChartSegment(
            startTime: Date(timeIntervalSince1970: Double(currentStart) / 1000),
            endTime:   Date(timeIntervalSince1970: Double(endMs) / 1000),
            status:    currentStatus
        ))

        return result
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.quaternarySystemFill).opacity(0.6))
        )
    }
}

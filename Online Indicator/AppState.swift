import Foundation

class AppState {

    static let shared = AppState()

    private let networkMonitor = NetworkMonitor()
    private let connectivityChecker = ConnectivityChecker()

    private var refreshTimer: Timer?
    private var debounceTimer: Timer?

    enum ConnectionStatus {
        case connected
        case blocked
        case noNetwork
    }

    private(set) var currentStatus: ConnectionStatus = .noNetwork

    var statusUpdateHandler: ((ConnectionStatus) -> Void)?

    var checkNowResultHandler: ((ConnectionStatus) -> Void)?

    var refreshInterval: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: "refreshInterval")
        return saved == 0 ? 5 : saved
    }

    // MARK: - Public Start

    func start() {

        // Listen for network interface changes (WiFi off, Ethernet unplugged)
        networkMonitor.pathChangedHandler = { [weak self] in
            self?.debouncedImmediateCheck()
        }

        networkMonitor.startMonitoring()

        startTimer()

        // Immediate outbound attempt on startup
        checkConnection()
    }

    // MARK: - Restart (when settings change)

    func restart() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        startTimer()
        checkConnection()
    }

    // MARK: - Immediate check (bypasses interval, triggered on demand)

    func checkNow() {
        checkConnection(onDemand: true)
    }

    // MARK: - Timer

    private func startTimer() {

        refreshTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkConnection()
        }
    }

    // MARK: - Debounce for rapid network changes

    private func debouncedImmediateCheck() {

        debounceTimer?.invalidate()

        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: false
        ) { [weak self] _ in
            self?.checkConnection()
        }
    }

    // MARK: - Core Logic

    private func checkConnection(onDemand: Bool = false) {

        if !networkMonitor.isConnected {
            let status = ConnectionStatus.noNetwork
            currentStatus = status
            statusUpdateHandler?(status)
            if onDemand { checkNowResultHandler?(status) }
            record(status: status, latencyMs: nil)
            return
        }

        connectivityChecker.checkOutboundConnection { [weak self] reachable, latencyMs in
            DispatchQueue.main.async {
                let status: ConnectionStatus = reachable ? .connected : .blocked
                self?.currentStatus = status
                self?.statusUpdateHandler?(status)
                if onDemand { self?.checkNowResultHandler?(status) }
                self?.record(status: status, latencyMs: latencyMs)
            }
        }
    }

    private func record(status: ConnectionStatus, latencyMs: Int?) {
        let statusString: String = {
            switch status {
            case .connected: return "connected"
            case .blocked:   return "blocked"
            case .noNetwork: return "noNetwork"
            }
        }()

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let ssid = SSIDManager.shared.currentSSID()
        let probeUrl = ConnectivityChecker.monitoringURLString

        HistoryStore.shared.insert(
            timestamp: timestamp,
            status: statusString,
            latencyMs: latencyMs,
            ssid: ssid,
            probeUrl: probeUrl
        )
    }
}

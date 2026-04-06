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

    var statusUpdateHandler: ((ConnectionStatus) -> Void)?

    var checkNowResultHandler: ((ConnectionStatus) -> Void)?

    var refreshInterval: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: "refreshInterval")
        return saved == 0 ? 30 : saved
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
            statusUpdateHandler?(status)
            if onDemand { checkNowResultHandler?(status) }
            return
        }

        connectivityChecker.checkOutboundConnection { [weak self] reachable in
            DispatchQueue.main.async {
                let status: ConnectionStatus = reachable ? .connected : .blocked
                self?.statusUpdateHandler?(status)
                if onDemand { self?.checkNowResultHandler?(status) }
            }
        }
    }
}

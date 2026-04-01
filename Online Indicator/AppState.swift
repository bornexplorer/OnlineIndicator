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
        checkConnection()
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

    private func checkConnection() {

        if !networkMonitor.isConnected {
            statusUpdateHandler?(.noNetwork)
            return
        }

        // Attempt outbound request
        connectivityChecker.checkOutboundConnection { [weak self] reachable in

            DispatchQueue.main.async {
                self?.statusUpdateHandler?(reachable ? .connected : .blocked)
            }
        }
    }
}

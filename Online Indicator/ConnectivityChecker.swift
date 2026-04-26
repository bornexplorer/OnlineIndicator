import Foundation

class ConnectivityChecker {

    static let defaultURLString = "http://captive.apple.com"

    static var monitoringURLString: String {
        let saved = UserDefaults.standard.string(forKey: "pingURL") ?? ""
        return saved.isEmpty ? defaultURLString : saved
    }

    private var currentTask: URLSessionDataTask?

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpAdditionalHeaders = ["Connection": "close"]
        return URLSession(configuration: configuration)
    }()

    func checkOutboundConnection(completion: @escaping (Bool, Int?) -> Void) {

        print("Attempting outbound connection to:", Self.monitoringURLString)

        guard let url = URL(string: Self.monitoringURLString) else {
            completion(false, nil)
            return
        }

        currentTask?.cancel()
        currentTask = nil

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let startTime = Date()

        let task = session.dataTask(with: request) { [weak self] _, response, error in

            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }

            self?.currentTask = nil

            if let error = error {
                print("Outbound Error:", error.localizedDescription)
                completion(false, nil)
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               (200...399).contains(httpResponse.statusCode) {
                completion(true, latencyMs)
            } else {
                completion(false, nil)
            }
        }

        currentTask = task
        task.resume()
    }
}

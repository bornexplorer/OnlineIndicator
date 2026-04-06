import Foundation
import AppKit

// MARK: - Semantic Version

private struct SemanticVersion: Comparable, Equatable {

    let components: [Int]

    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s = String(s.dropFirst()) }
        for delimiter in ["-", "+"] {
            if let idx = s.firstIndex(of: delimiter.first!) {
                s = String(s[..<idx])
            }
        }
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        components = parts
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let len = max(lhs.components.count, rhs.components.count)
        for i in 0..<len {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l < r { return true  }
            if l > r { return false }
        }
        return false
    }
}

// MARK: - UpdateChecker

class UpdateChecker {

    static let repoOwner = "bornexplorer"
    static let repoName  = "OnlineIndicator"

    private static var apiURL: URL? {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")
    }

    enum UpdateResult {
        case upToDate
        case updateAvailable(releaseTag: String, pageURL: URL)
        case error(String)
    }

    static func check(completion: @escaping (UpdateResult) -> Void) {
        guard let url = apiURL else {
            completion(.error("Invalid repository URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.error(error.localizedDescription))
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    completion(.error("Invalid response from GitHub"))
                    return
                }

                if let message = json["message"] as? String {
                    completion(.error(message))
                    return
                }

                guard let tag = json["tag_name"] as? String,
                      let pageURLString = json["html_url"] as? String,
                      let pageURL = URL(string: pageURLString)
                else {
                    completion(.error("Unexpected response format"))
                    return
                }

                guard let remote = SemanticVersion(tag),
                      let local  = SemanticVersion(AppInfo.marketingVersion)
                else {
                    completion(.error("Could not parse version numbers"))
                    return
                }

                guard remote > local else {
                    completion(.upToDate)
                    return
                }

                completion(.updateAvailable(releaseTag: tag, pageURL: pageURL))
            }
        }.resume()
    }
}

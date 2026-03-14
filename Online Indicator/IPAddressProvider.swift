import Foundation
import Darwin
import CoreWLAN

struct IPAddressProvider {

    struct Addresses {
        var ipv4: String?
        var ipv6: String?
        var wifiName: String?
    }

    /// Reads the current IPv4, IPv6, and Wi-Fi network name from the active primary network interface.
    /// Prefers en0 (Wi-Fi) then en1/en2 (Ethernet). Strips the scope-ID suffix from IPv6.
    static func current() -> Addresses {
        var result = Addresses()
        result.wifiName = CWWiFiClient.shared().interface()?.ssid()

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return result }
        defer { freeifaddrs(ifaddr) }

        // Priority order for interface names
        let preferred = ["en0", "en1", "en2", "en3"]

        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            guard preferred.contains(name),
                  let addr = current.pointee.ifa_addr else { continue }

            let family = addr.pointee.sa_family
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

            if family == UInt8(AF_INET), result.ipv4 == nil {
                guard getnameinfo(addr,
                                  socklen_t(addr.pointee.sa_len),
                                  &hostname, socklen_t(hostname.count),
                                  nil, 0, NI_NUMERICHOST) == 0 else { continue }
                result.ipv4 = String(cString: hostname)
            }

            if family == UInt8(AF_INET6), result.ipv6 == nil {
                guard getnameinfo(addr,
                                  socklen_t(addr.pointee.sa_len),
                                  &hostname, socklen_t(hostname.count),
                                  nil, 0, NI_NUMERICHOST) == 0 else { continue }
                var address = String(cString: hostname)
                if let percent = address.firstIndex(of: "%") {
                    address = String(address[..<percent])
                }
                result.ipv6 = address
            }
        }

        return result
    }
}

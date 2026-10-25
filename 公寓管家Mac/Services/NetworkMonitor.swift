import Foundation
import Network

// MARK: - 网络监控（NWPathMonitor 包装）

enum NetworkMonitor {
    private static let monitor = NWPathMonitor()
    private static let queue = DispatchQueue(label: "network.monitor")

    static var isConnected = false
    static var isExpensive = false

    static func start() {
        monitor.pathUpdateHandler = { path in
            isConnected = path.status == .satisfied
            isExpensive = path.isExpensive
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .macNetworkChanged, object: nil, userInfo: ["connected": isConnected])
            }
        }
        monitor.start(queue: queue)
    }
}

extension Notification.Name {
    static let macNetworkChanged = Notification.Name("macNetworkChanged")
}

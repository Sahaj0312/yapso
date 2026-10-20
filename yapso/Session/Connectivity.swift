import Network
import Observation

/// Whether the device has a network path, so offline screens can retry by themselves once it's back.
@Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in Connectivity.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.sahaj03.yapso.connectivity"))
    }
}

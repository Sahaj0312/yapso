import CoreMotion
import Observation

/// How far the phone is tilted from where it was when tracking started, roughly -1...1 on each axis.
/// Drives the profile card's foil. Device motion needs no permission.
@Observable
final class DeviceTilt {
    private(set) var x: Double = 0
    private(set) var y: Double = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var reference: CMAttitude?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude.copy() as? CMAttitude else { return }
            if let reference { attitude.multiply(byInverseOf: reference) } else { reference = attitude.copy() as? CMAttitude }
            // About 30 degrees each way covers the full effect; smoothed so it glides rather than jitters.
            let targetX = max(-1, min(1, attitude.roll / 0.5))
            let targetY = max(-1, min(1, attitude.pitch / 0.5))
            x += (targetX - x) * 0.15
            y += (targetY - y) * 0.15
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
    }
}

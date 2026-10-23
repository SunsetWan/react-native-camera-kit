/// Runs on the capture session queue. Graph changes must wait for native capture completion,
/// even when the public request has already been cancelled.
final class CaptureConfigurationGate {
    private var captureIDs: Set<Int64> = []
    private var pending: [() -> Void] = []

    func beginCapture(id: Int64) { captureIDs.insert(id) }

    func performWhenIdle(_ operation: @escaping () -> Void) {
        if captureIDs.isEmpty { operation() } else { pending.append(operation) }
    }

    func endCapture(id: Int64) {
        guard captureIDs.remove(id) != nil, captureIDs.isEmpty else { return }
        let operations = pending
        pending.removeAll()
        operations.forEach { $0() }
    }
}

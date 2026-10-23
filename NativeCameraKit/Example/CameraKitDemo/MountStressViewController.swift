import UIKit

final class MountStressViewController: UIViewController {
    private let intervalField = UITextField()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let cameraContainer = UIView()
    private var cameraController: CameraViewController?
    private var timer: Timer?
    private var startTime: Date?
    private var mountCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Mount Stress Test"
        view.backgroundColor = .systemBackground
        intervalField.text = "1000"
        intervalField.placeholder = "Interval in milliseconds"
        intervalField.keyboardType = .numberPad
        intervalField.borderStyle = .roundedRect
        intervalField.accessibilityLabel = "Mount interval in milliseconds"
        intervalField.accessibilityIdentifier = "stress-interval"
        let intervalLabel = UILabel()
        intervalLabel.text = "Interval (ms)"
        intervalLabel.setContentHuggingPriority(.required, for: .horizontal)
        let intervalRow = UIStackView(arrangedSubviews: [intervalLabel, intervalField])
        intervalRow.spacing = 12
        startButton.setTitle("Start", for: .normal)
        startButton.accessibilityIdentifier = "start-stress-test"
        startButton.addTarget(self, action: #selector(confirmStart), for: .touchUpInside)
        stopButton.setTitle("Stop", for: .normal)
        stopButton.accessibilityIdentifier = "stop-stress-test"
        stopButton.isEnabled = false
        stopButton.addTarget(self, action: #selector(stop), for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [startButton, stopButton])
        controls.distribution = .fillEqually
        statusLabel.text = "Ready. Run for at least two minutes on an iPhone 17 Pro."
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.accessibilityIdentifier = "stress-status"
        cameraContainer.backgroundColor = .black
        let stack = UIStackView(arrangedSubviews: [intervalRow, controls, statusLabel, cameraContainer])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    @objc private func confirmStart() {
        view.endEditing(true)
        guard let milliseconds = Double(intervalField.text ?? ""), milliseconds.isFinite, milliseconds > 0 else {
            statusLabel.text = "Enter a positive interval in milliseconds."
            return
        }
        let alert = UIAlertController(
            title: "Run for at least two minutes",
            message: "The original example recommends an iPhone 17 Pro. Press Stop when you finish. Simulator results do not validate camera hardware.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Start", style: .default) { [weak self] _ in
            self?.start(interval: milliseconds / 1000)
        })
        present(alert, animated: true)
    }

    private func start(interval: TimeInterval) {
        stop()
        mountCount = 0
        startTime = Date()
        startButton.isEnabled = false
        stopButton.isEnabled = true
        intervalField.isEnabled = false
        toggleCamera()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.toggleCamera()
        }
    }

    private func toggleCamera() {
        if cameraController != nil {
            removeCamera()
        } else {
            let camera = CameraViewController(stress: true)
            addChild(camera)
            camera.view.frame = cameraContainer.bounds
            camera.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cameraContainer.addSubview(camera.view)
            camera.didMove(toParent: self)
            cameraController = camera
            mountCount += 1
        }
        let elapsed = Int(Date().timeIntervalSince(startTime ?? Date()))
        let state = cameraController == nil ? "unmounted" : "mounted"
        statusLabel.text = "\(mountCount) mounts · \(elapsed) s · \(state)"
    }

    @objc private func stop() {
        timer?.invalidate()
        timer = nil
        removeCamera()
        if let startTime {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            statusLabel.text = "Stopped · \(mountCount) mounts · \(elapsed) s"
        }
        startTime = nil
        startButton.isEnabled = true
        stopButton.isEnabled = false
        intervalField.isEnabled = true
    }

    private func removeCamera() {
        guard let camera = cameraController else { return }
        camera.willMove(toParent: nil)
        camera.view.removeFromSuperview()
        camera.removeFromParent()
        cameraController = nil
    }
}

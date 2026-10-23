import NativeCameraKit
import UIKit

final class CameraSettingsViewController: UITableViewController {
    private var configuration: CameraConfiguration
    private let onChange: (CameraConfiguration) -> Void
    private let sections = ["Photo", "Focus and zoom", "Barcode scanner", "Face detection", "Startup", "Permissions"]
    private let rowCounts = [6, 6, 7, 2, 1, 1]

    init(configuration: CameraConfiguration, onChange: @escaping (CameraConfiguration) -> Void) {
        self.configuration = configuration
        self.onChange = onChange
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Camera settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rowCounts[section] }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section] }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "Ratio guides do not crop the saved photo. Photos stay in temporary storage unless you export them."
        case 1:
            return "Uncontrolled zoom follows pinch gestures. Moving the main zoom slider enables controlled zoom. "
                + "A focus timeout of 0 keeps tap focus until it resets."
        case 2: return "An empty format selection allows all supported formats. When the frame is visible, only codes inside it are scanned."
        case 3: return "Apple Vision runs on the device. Green boxes indicate a centered face directed toward the camera."
        case 4: return "Deferred start applies on supported iOS 26 devices. It can show the preview sooner and delay the first photo."
        default: return "Camera access is required on a physical device. The simulator produces a test JPEG."
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0: return photoCell(at: indexPath.row)
        case 1: return focusAndZoomCell(at: indexPath.row)
        case 2: return scannerCell(at: indexPath.row)
        case 3: return faceDetectionCell(at: indexPath.row)
        case 4:
            return toggle("Deferred photo output", isOn: configuration.iOsDeferredStart) { $0.iOsDeferredStart = $1 }
        default:
            let cell = cell("Open system settings")
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    private func photoCell(at row: Int) -> UITableViewCell {
        switch row {
        case 0:
            return choice("Camera", key: \.cameraType, options: [("Back", .back), ("Front", .front)])
        case 1:
            return choice("Flash", key: \.flashMode, options: [("Auto", .auto), ("On", .on), ("Off", .off)])
        case 2:
            return choice("Photo priority", key: \.maxPhotoQualityPrioritization, options: [("Balanced", .balanced), ("Quality", .quality), ("Speed", .speed)])
        case 3:
            return choice("Preview resize", key: \.resizeMode, options: [("Contain", .contain), ("Cover", .cover)])
        case 4:
            return choice("Ratio guide", key: \.ratioOverlay, options: [("None", nil), ("1:1", "1:1"), ("4:3", "4:3"), ("16:9", "16:9")])
        default:
            return choice("Guide color", key: \.ratioOverlayColor, options: [
                ("Default", nil), ("Dark", UIColor.black.withAlphaComponent(0.6)),
                ("White", UIColor.white.withAlphaComponent(0.45))
            ])
        }
    }

    private func focusAndZoomCell(at row: Int) -> UITableViewCell {
        switch row {
        case 0:
            return toggle("Tap to focus", isOn: configuration.focusMode == .on) { $0.focusMode = $1 ? .on : .off }
        case 1:
            return toggle("Pinch to zoom", isOn: configuration.zoomMode == .on) { $0.zoomMode = $1 ? .on : .off }
        case 2:
            return toggle("Controlled zoom", isOn: configuration.zoom != nil) { $0.zoom = $1 ? 1 : nil }
        case 3:
            return choice("Maximum zoom", key: \.maxZoom, options: [("2×", 2), ("5×", 5), ("10×", 10), ("Device limit", nil)])
        case 4:
            return stepper("Focus timeout", key: \.resetFocusTimeout, range: 0...10000, step: 1000)
        default:
            return toggle("Reset focus on motion", isOn: configuration.resetFocusWhenMotionDetected) { $0.resetFocusWhenMotionDetected = $1 }
        }
    }

    private func scannerCell(at row: Int) -> UITableViewCell {
        switch row {
        case 0:
            return toggle("Scan barcodes", isOn: configuration.scanBarcode) { $0.scanBarcode = $1 }
        case 1:
            return toggle("Show scan frame", isOn: configuration.showFrame) { $0.showFrame = $1 }
        case 2:
            let cell = cell("Allowed formats")
            cell.detailTextLabel?.text = configuration.allowedBarcodeTypes.isEmpty ? "All" : "\(configuration.allowedBarcodeTypes.count) selected"
            cell.accessoryType = .disclosureIndicator
            return cell
        case 3:
            return stepper("Scan throttle", key: \.scanThrottleDelay, range: 0...10000, step: 250)
        case 4:
            return choice("Scan frame size", key: \.barcodeFrameSize, options: [
                ("Default", nil), ("Square", CGSize(width: 240, height: 240)), ("Wide", CGSize(width: 300, height: 150))
            ])
        case 5:
            return choice("Frame color", key: \.frameColor, options: [("White", .white), ("Yellow", .yellow), ("Green", .green)])
        default:
            return choice("Laser color", key: \.laserColor, options: [("Red", .red), ("Green", .green), ("Blue", .systemBlue)])
        }
    }

    private func faceDetectionCell(at row: Int) -> UITableViewCell {
        switch row {
        case 0:
            return toggle("Detect faces", isOn: configuration.faceDetectionEnabled) { $0.faceDetectionEnabled = $1 }
        default:
            return stepper("Face throttle", key: \.faceDetectionThrottleMs, range: 0...1000, step: 50)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath == IndexPath(row: 2, section: 2) {
            let formats = BarcodeFormatsViewController(selected: configuration.allowedBarcodeTypes) { [weak self] selected in
                guard let self else { return }
                configuration.allowedBarcodeTypes = selected
                onChange(configuration)
                tableView.reloadRows(at: [indexPath], with: .none)
            }
            navigationController?.pushViewController(formats, animated: true)
        } else if indexPath.section == 5, let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func cell(_ title: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        return cell
    }

    private func toggle(_ title: String, isOn: Bool, update: @escaping (inout CameraConfiguration, Bool) -> Void) -> UITableViewCell {
        let cell = cell(title)
        cell.selectionStyle = .none
        let control = UISwitch()
        control.isOn = isOn
        control.accessibilityLabel = title
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let self, let control else { return }
            update(&configuration, control.isOn)
            onChange(configuration)
        }, for: .valueChanged)
        cell.accessoryView = control
        return cell
    }

    private func choice<Value: Equatable>(
        _ title: String,
        key: WritableKeyPath<CameraConfiguration, Value>,
        options: [(String, Value)]
    ) -> UITableViewCell {
        let cell = cell(title)
        cell.selectionStyle = .none
        let button = UIButton(type: .system)
        button.setTitle(options.first { $0.1 == configuration[keyPath: key] }?.0 ?? "Custom", for: .normal)
        button.accessibilityLabel = title
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: options.map { label, value in
            UIAction(title: label) { [weak self, weak button] _ in
                guard let self else { return }
                configuration[keyPath: key] = value
                onChange(configuration)
                button?.setTitle(label, for: .normal)
                button?.sizeToFit()
            }
        })
        button.sizeToFit()
        cell.accessoryView = button
        return cell
    }

    private func stepper(_ title: String, key: WritableKeyPath<CameraConfiguration, Int>, range: ClosedRange<Int>, step: Double) -> UITableViewCell {
        let cell = cell(title)
        cell.selectionStyle = .none
        cell.detailTextLabel?.text = "\(configuration[keyPath: key]) ms"
        let control = UIStepper()
        control.minimumValue = Double(range.lowerBound)
        control.maximumValue = Double(range.upperBound)
        control.stepValue = step
        control.value = Double(configuration[keyPath: key])
        control.accessibilityLabel = title
        control.addAction(UIAction { [weak self, weak cell, weak control] _ in
            guard let self, let control else { return }
            configuration[keyPath: key] = Int(control.value)
            cell?.detailTextLabel?.text = "\(Int(control.value)) ms"
            onChange(configuration)
        }, for: .valueChanged)
        cell.accessoryView = control
        return cell
    }
}

private final class BarcodeFormatsViewController: UITableViewController {
    private let formats = CodeFormat.allCases.filter { $0 != .unknown }
    private var selected: Set<CodeFormat>
    private let onChange: ([CodeFormat]) -> Void

    init(selected: [CodeFormat], onChange: @escaping ([CodeFormat]) -> Void) {
        self.selected = Set(selected)
        self.onChange = onChange
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Barcode formats"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Allow all", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            selected.removeAll()
            onChange([])
            tableView.reloadData()
        })
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { formats.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let format = formats[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = format.rawValue
        cell.accessoryType = selected.contains(format) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let format = formats[indexPath.row]
        if selected.contains(format) { selected.remove(format) } else { selected.insert(format) }
        onChange(formats.filter { selected.contains($0) })
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}

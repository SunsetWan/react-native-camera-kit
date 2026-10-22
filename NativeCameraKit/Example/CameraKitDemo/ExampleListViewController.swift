import UIKit

final class ExampleListViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Native Camera Kit"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.accessibilityIdentifier = "example-list"
        navigationItem.backButtonTitle = "Examples"
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : 1 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Examples" : "Lifecycle testing"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0
            ? "Take a five-photo burst or scan QR and EAN-13 codes. Camera settings expose all native options."
            : "Repeatedly create and remove a camera while changing zoom. Physical camera acceptance requires a device."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.accessoryType = .disclosureIndicator
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            cell.textLabel?.text = "Camera"
            cell.detailTextLabel?.text = "Photo capture, focus, zoom, and faces"
            cell.imageView?.image = UIImage(systemName: "camera")
            cell.accessibilityIdentifier = "open-camera"
        case (0, 1):
            cell.textLabel?.text = "Barcode Scanner"
            cell.detailTextLabel?.text = "QR and EAN-13 with scan-frame filtering"
            cell.imageView?.image = UIImage(systemName: "barcode.viewfinder")
            cell.accessibilityIdentifier = "open-scanner"
        default:
            cell.textLabel?.text = "Mount Stress Test"
            cell.detailTextLabel?.text = "Configurable mount and unmount interval"
            cell.imageView?.image = UIImage(systemName: "repeat")
            cell.accessibilityIdentifier = "open-stress-test"
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let destination: UIViewController
        switch (indexPath.section, indexPath.row) {
        case (0, 0): destination = CameraViewController()
        case (0, 1): destination = CameraViewController(mode: .scanner)
        default: destination = MountStressViewController()
        }
        navigationController?.pushViewController(destination, animated: true)
    }
}

import UIKit

/// A deterministic local scene keeps simulator capture independent from hardware and networking.
final class SimulatorPreviewView: UIView {
    let zoomLabel = UILabel()
    let focusAtLabel = UILabel()
    let torchModeLabel = UILabel()
    let flashModeLabel = UILabel()
    let cameraTypeLabel = UILabel()
    let resizeModeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.09, green: 0.15, blue: 0.25, alpha: 1)
        let stack = UIStackView(arrangedSubviews: [cameraTypeLabel, zoomLabel, focusAtLabel,
                                                 torchModeLabel, flashModeLabel, resizeModeLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
        for label in [zoomLabel, focusAtLabel, torchModeLabel, flashModeLabel, cameraTypeLabel, resizeModeLabel] {
            label.textColor = .white
            label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            label.numberOfLines = 0
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        Self.drawScene(in: bounds)
    }

    func snapshot() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 480, height: 640), format: format).image { _ in
            let rect = CGRect(x: 0, y: 0, width: 480, height: 640)
            backgroundColor?.setFill()
            UIRectFill(rect)
            Self.drawScene(in: rect)
            let text = ["NativeCameraKit Simulator", cameraTypeLabel.text ?? "", zoomLabel.text ?? ""].joined(separator: "\n")
            (text as NSString).draw(in: CGRect(x: 24, y: 24, width: 432, height: 100), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 17, weight: .medium),
                .foregroundColor: UIColor.white
            ])
        }
    }

    private static func drawScene(in rect: CGRect) {
        let colors: [UIColor] = [.systemTeal, .systemOrange, .systemPink]
        for (index, color) in colors.enumerated() {
            let size = rect.width * 0.28
            let x = rect.width * (0.08 + Double(index) * 0.28)
            let y = rect.height * (0.42 + Double(index % 2) * 0.12)
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: x, y: y, width: size, height: size * 1.25)).fill()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x + size / 2, y: y + size * 1.25))
            path.addQuadCurve(to: CGPoint(x: x + size / 2, y: rect.height),
                              controlPoint: CGPoint(x: x + size, y: rect.height * 0.9))
            UIColor.white.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}

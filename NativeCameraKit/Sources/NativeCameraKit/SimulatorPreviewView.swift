import UIKit

/// An animated local scene that provides the same simulator controls as the camera preview.
final class SimulatorPreviewView: UIView {
    let zoomLabel = UILabel()
    let focusAtLabel = UILabel()
    let torchModeLabel = UILabel()
    let flashModeLabel = UILabel()
    let cameraTypeLabel = UILabel()
    let resizeModeLabel = UILabel()

    private var balloonLayer = CALayer()
    private var sceneSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.insertSublayer(balloonLayer, at: 0)
        let labels = [zoomLabel, focusAtLabel, torchModeLabel, flashModeLabel, cameraTypeLabel, resizeModeLabel]
        let stack = UIStackView(arrangedSubviews: labels)
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
        for label in labels {
            label.textColor = .white
            label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            label.shadowColor = .black
            label.shadowOffset = CGSize(width: 1, height: 1)
            label.numberOfLines = 0
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if sceneSize != bounds.size { randomize() }
    }

    func randomize() {
        sceneSize = bounds.size
        backgroundColor = UIColor(hue: .random(in: 0...1), saturation: 1, brightness: 1, alpha: 1)
        balloonLayer.removeFromSuperlayer()
        balloonLayer = CALayer()
        balloonLayer.frame = bounds
        layer.insertSublayer(balloonLayer, at: 0)
        guard bounds.width > 0, bounds.height > 0 else { return }
        for _ in 0..<5 { addBalloon() }
    }

    /// Captures the displayed scene and labels, with a timestamp added to the saved photo.
    func snapshot(withTimestamp showTimestamp: Bool = true) -> UIImage {
        let originalBounds = bounds
        let originalAlpha = alpha
        let needsFallbackSize = bounds.isEmpty
        if needsFallbackSize { bounds.size = CGSize(width: 480, height: 640) }
        // The shutter animation changes preview opacity; it must not darken the next photo in a burst.
        layer.removeAnimation(forKey: "opacity")
        alpha = 1
        layoutIfNeeded()
        defer {
            alpha = originalAlpha
            if bounds != originalBounds { bounds = originalBounds }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = needsFallbackSize ? 1 : (window?.screen.scale ?? max(1, traitCollection.displayScale))
        format.opaque = true
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            if window == nil || !drawHierarchy(in: bounds, afterScreenUpdates: true) {
                layer.render(in: context.cgContext)
            }
            if showTimestamp { drawTimestamp() }
        }
    }

    private func drawTimestamp() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date()) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor.white,
            .backgroundColor: UIColor.black.withAlphaComponent(0.65)
        ]
        let size = timestamp.size(withAttributes: attributes)
        timestamp.draw(at: CGPoint(x: 16, y: max(0, bounds.height - size.height - 16)), withAttributes: attributes)
    }

    private func addBalloon() {
        let stringLength: CGFloat = 200
        let radius = CGFloat.random(in: 50...150)
        let stretch = radius / 3
        let balloon = CALayer()
        balloon.frame = CGRect(
            x: CGFloat.random(in: 0...bounds.width) - radius,
            y: CGFloat.random(in: 0...(bounds.height + radius + stringLength)) - radius,
            width: radius * 2,
            height: radius * 2 + stringLength
        )
        let hue = CGFloat.random(in: 0...1)
        let circle = CAShapeLayer()
        circle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2 + stretch)).cgPath
        circle.fillColor = UIColor(hue: hue, saturation: 1, brightness: 0.95, alpha: 1).cgColor
        let reflection = CAShapeLayer()
        reflection.path = UIBezierPath(ovalIn: CGRect(x: radius / 2, y: radius / 2, width: radius * 0.7, height: radius * 0.7)).cgPath
        reflection.fillColor = UIColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).cgColor
        let string = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: radius, y: radius * 2))
        path.addQuadCurve(to: CGPoint(x: radius * 2, y: radius * 2 + stringLength),
                          controlPoint: CGPoint(x: radius, y: radius * 2 + stringLength / 2))
        string.path = path.cgPath
        string.fillColor = nil
        string.strokeColor = UIColor.darkGray.cgColor
        string.lineWidth = radius * 0.05
        balloon.addSublayer(string)
        circle.addSublayer(reflection)
        balloon.addSublayer(circle)
        balloonLayer.addSublayer(balloon)
        animate(balloon)
    }

    private func animate(_ balloon: CALayer) {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.7
        scale.toValue = 1
        scale.duration = 10
        scale.autoreverses = true
        scale.repeatCount = .greatestFiniteMagnitude
        scale.isRemovedOnCompletion = false
        let move = CABasicAnimation(keyPath: "position.y")
        move.fromValue = balloon.position.y
        move.toValue = -balloon.bounds.height
        move.duration = .random(in: 30...100)
        move.repeatCount = .greatestFiniteMagnitude
        move.isRemovedOnCompletion = false
        balloon.add(scale, forKey: "scale")
        balloon.add(move, forKey: "move")
    }
}

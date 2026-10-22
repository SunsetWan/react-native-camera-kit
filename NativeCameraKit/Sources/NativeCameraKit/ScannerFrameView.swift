import UIKit

final class ScannerFrameView: UIView {
    private let laserView = UIView()
    private let frameViews = (0..<8).map { _ in UIView() }
    private var wantsAnimation = false
    private var animatedSize = CGSize.zero

    init(frameColor: UIColor, laserColor: UIColor) {
        super.init(frame: .zero)
        laserView.backgroundColor = laserColor
        addSubview(laserView)
        for view in frameViews {
            view.backgroundColor = frameColor
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, view) in frameViews.enumerated() { view.frame = cornerFrame(at: index) }
        if animatedSize != bounds.size {
            laserView.layer.removeAnimation(forKey: "scan")
            animatedSize = bounds.size
        }
        laserView.frame = CGRect(x: 2, y: 2, width: max(0, bounds.width - 4), height: 2)
        updateAnimation()
    }

    func startAnimatingScanner() {
        wantsAnimation = true
        updateAnimation()
    }

    func stopAnimatingScanner() {
        wantsAnimation = false
        laserView.layer.removeAnimation(forKey: "scan")
        laserView.isHidden = true
    }

    func update(frameColor: UIColor) { frameViews.forEach { $0.backgroundColor = frameColor } }
    func update(laserColor: UIColor) { laserView.backgroundColor = laserColor }

    private func updateAnimation() {
        laserView.isHidden = !wantsAnimation
        guard wantsAnimation, bounds.height > 6, laserView.layer.animation(forKey: "scan") == nil else { return }
        let animation = CABasicAnimation(keyPath: "position.y")
        animation.fromValue = 3
        animation.toValue = bounds.height - 3
        animation.duration = 3
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        laserView.layer.add(animation, forKey: "scan")
    }

    private func cornerFrame(at index: Int) -> CGRect {
        let length: CGFloat = min(20, min(bounds.width, bounds.height))
        let line: CGFloat = 2
        switch index {
        case 0: return CGRect(x: 0, y: 0, width: line, height: length)
        case 1: return CGRect(x: 0, y: 0, width: length, height: line)
        case 2: return CGRect(x: bounds.width - length, y: 0, width: length, height: line)
        case 3: return CGRect(x: bounds.width - line, y: 0, width: line, height: length)
        case 4: return CGRect(x: bounds.width - line, y: bounds.height - length, width: line, height: length)
        case 5: return CGRect(x: bounds.width - length, y: bounds.height - line, width: length, height: line)
        case 6: return CGRect(x: 0, y: bounds.height - line, width: length, height: line)
        default: return CGRect(x: 0, y: bounds.height - length, width: line, height: length)
        }
    }
}

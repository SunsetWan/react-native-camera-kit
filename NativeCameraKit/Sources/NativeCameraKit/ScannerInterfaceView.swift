import UIKit

final class ScannerInterfaceView: UIView {
    private let frameView: ScannerFrameView
    private let overlays = (0..<4).map { _ in UIView() }
    private var barcodeFrameSize = CGSize(width: 300, height: 150)

    init(frameColor: UIColor, laserColor: UIColor) {
        frameView = ScannerFrameView(frameColor: frameColor, laserColor: laserColor)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(frameView)
        for overlay in overlays {
            overlay.backgroundColor = .black.withAlphaComponent(0.4)
            addSubview(overlay)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var frameSize: CGRect {
        let width = max(0, barcodeFrameSize.width)
        let height = max(0, barcodeFrameSize.height)
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let region = frameSize
        frameView.frame = region
        // Keep the requested frame size; only the surrounding masks are clipped to the preview.
        let visible = region.intersection(bounds)
        guard !visible.isNull else {
            overlays.forEach { $0.frame = .zero }
            return
        }
        overlays[0].frame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: visible.minY - bounds.minY)
        overlays[1].frame = CGRect(x: bounds.minX, y: visible.maxY, width: bounds.width, height: bounds.maxY - visible.maxY)
        overlays[2].frame = CGRect(x: bounds.minX, y: visible.minY, width: visible.minX - bounds.minX, height: visible.height)
        overlays[3].frame = CGRect(x: visible.maxX, y: visible.minY, width: bounds.maxX - visible.maxX, height: visible.height)
    }

    func startAnimatingScanner() { frameView.startAnimatingScanner() }
    func stopAnimatingScanner() { frameView.stopAnimatingScanner() }
    func update(frameColor: UIColor) { frameView.update(frameColor: frameColor) }
    func update(laserColor: UIColor) { frameView.update(laserColor: laserColor) }

    func update(frameSize: CGSize) {
        barcodeFrameSize = CGSize(
            width: frameSize.width.isFinite ? frameSize.width : 300,
            height: frameSize.height.isFinite ? frameSize.height : 150
        )
        setNeedsLayout()
    }
}

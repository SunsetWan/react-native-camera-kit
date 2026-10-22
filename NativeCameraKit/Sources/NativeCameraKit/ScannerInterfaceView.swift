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
        let width = min(bounds.width, max(0, barcodeFrameSize.width))
        let height = min(bounds.height, max(0, barcodeFrameSize.height))
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let region = frameSize
        frameView.frame = region
        overlays[0].frame = CGRect(x: 0, y: 0, width: bounds.width, height: region.minY)
        overlays[1].frame = CGRect(x: 0, y: region.maxY, width: bounds.width, height: bounds.height - region.maxY)
        overlays[2].frame = CGRect(x: 0, y: region.minY, width: region.minX, height: region.height)
        overlays[3].frame = CGRect(x: region.maxX, y: region.minY, width: bounds.width - region.maxX, height: region.height)
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

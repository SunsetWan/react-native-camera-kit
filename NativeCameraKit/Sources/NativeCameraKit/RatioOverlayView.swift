import UIKit

/// The source API uses height:width, so 16:9 describes a portrait guide.
struct RatioOverlayData: CustomStringConvertible {
    let width: Float
    let height: Float
    let ratio: Float

    init(from inputString: String) {
        let values = inputString.split(separator: ":", omittingEmptySubsequences: false)
        if values.count == 2,
           let height = Float(values[0]), let width = Float(values[1]),
           height.isFinite, width.isFinite, height > 0, width > 0,
           (width / height).isFinite, width / height > 0 {
            self.height = height
            self.width = width
            ratio = width / height
        } else {
            height = 0
            width = 0
            ratio = 0
        }
    }

    var description: String { "height:\(height) width:\(width) ratio:\(ratio)" }
}

/// A guide only. The camera still returns the full captured photo.
final class RatioOverlayView: UIView {
    private var ratioData: RatioOverlayData
    private let firstMask = UIView()
    private let secondMask = UIView()

    init(frame: CGRect, ratioString: String, overlayColor: UIColor?) {
        ratioData = RatioOverlayData(from: ratioString)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(firstMask)
        addSubview(secondMask)
        setColor(overlayColor ?? .black.withAlphaComponent(0.3))
        updateMasks()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMasks()
    }

    func setRatio(_ ratioString: String) {
        ratioData = RatioOverlayData(from: ratioString)
        UIView.animate(withDuration: 0.2) { self.updateMasks() }
    }

    func setColor(_ color: UIColor) {
        firstMask.backgroundColor = color
        secondMask.backgroundColor = color
    }

    private func updateMasks() {
        guard ratioData.ratio > 0, bounds.width > 0, bounds.height > 0 else {
            firstMask.frame = .zero
            secondMask.frame = .zero
            isHidden = true
            return
        }
        isHidden = false
        let aspectRatio = CGFloat(ratioData.ratio)
        if bounds.width / bounds.height > aspectRatio {
            let guideWidth = bounds.height * aspectRatio
            let maskWidth = (bounds.width - guideWidth) / 2
            firstMask.frame = CGRect(x: bounds.minX, y: bounds.minY, width: maskWidth, height: bounds.height)
            secondMask.frame = CGRect(x: bounds.maxX - maskWidth, y: bounds.minY, width: maskWidth, height: bounds.height)
        } else {
            let guideHeight = bounds.width / aspectRatio
            let maskHeight = (bounds.height - guideHeight) / 2
            firstMask.frame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: maskHeight)
            secondMask.frame = CGRect(x: bounds.minX, y: bounds.maxY - maskHeight, width: bounds.width, height: maskHeight)
        }
    }
}

import ImageIO
import NativeCameraKit
import UIKit

final class PhotoViewController: UIViewController, UIScrollViewDelegate {
    private let photo: CapturedPhoto
    private let imageView = UIImageView()

    init(photo: CapturedPhoto) {
        self.photo = photo
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Captured photo"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .action, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let activity = UIActivityViewController(activityItems: [photo.url], applicationActivities: nil)
            activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            present(activity, animated: true)
        })

        let scroll = UIScrollView()
        scroll.delegate = self
        scroll.maximumZoomScale = 6
        scroll.minimumZoomScale = 1
        scroll.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = Self.thumbnail(at: photo.url, maximumPixelSize: 2048)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Captured image"
        imageView.accessibilityIdentifier = "captured-image"
        scroll.addSubview(imageView)

        let details = UILabel()
        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(photo.size), countStyle: .file)
        details.text = "\(photo.width) × \(photo.height) · \(fileSize)\n\(photo.name)\n"
            + "Temporary file — use Share to keep a copy."
        details.font = .preferredFont(forTextStyle: .caption1)
        details.adjustsFontForContentSizeCategory = true
        details.textColor = .secondaryLabel
        details.numberOfLines = 0
        details.textAlignment = .center
        details.accessibilityIdentifier = "photo-details"
        details.setContentCompressionResistancePriority(.required, for: .vertical)
        details.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.addSubview(details)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: details.topAnchor, constant: -12),
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            details.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            details.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            details.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    static func thumbnail(at url: URL, maximumPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

# NativeCameraKit

A standalone Swift camera library and UIKit example for iOS 18 and later. It uses AVFoundation, Vision, UIKit, and an optional SwiftUI adapter. It has no React Native, CocoaPods, JavaScript, or third-party runtime dependency.

This port uses the iOS behavior of React Native Camera Kit v18.0.1 (`a2a81ce`) as its baseline. The existing React Native library remains available in this repository. The native implementation is under `NativeCameraKit/` and the Swift Package manifest is at the repository root.

## Open the UIKit example

Open `NativeCameraKit/Example/CameraKitDemo.xcodeproj` in Xcode 26 or later. Select the example scheme, then run on an iPhone or iPad. Set your own signing team for a physical device. The simulator provides an animated balloon scene, live control labels, and timestamped JPEG captures. It does not provide a camera or live detector.

The home screen opens three UIKit examples: Camera, Barcode / QR, and Mount Stress Test. Camera includes camera switching, flash, torch, focus, pinch and controlled zoom, five-photo bursts with timing, face bounds, aspect-ratio guides, photo quality, hardware capture, and a captured-photo viewer. The scanner starts with QR/EAN-13 filters, a 300 × 150 scan frame, vibration, and a result that clears after two seconds. The settings screen exposes timing and appearance controls. The stress screen repeatedly mounts and removes a camera at an editable interval; the camera screen also has a random-zoom stress mode.

## Add the package

Add this repository URL with Xcode's **Add Package Dependencies** command and select `NativeCameraKit`. Until this change is merged, select its PR branch. For a local checkout, add the repository root as a local package.

Add a camera usage description to the host application's Info.plist:

```xml
<key>NSCameraUsageDescription</key>
<string>Take photos and scan codes.</string>
```

Photo capture writes JPEG files into the application's cache directory. Photo Library permission is not required. Move a file to permanent storage if it must outlive the cache.

## UIKit

```swift
import NativeCameraKit
import UIKit

final class CameraViewController: UIViewController {
    private let camera = CameraView()

    override func viewDidLoad() {
        super.viewDidLoad()
        camera.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(camera)
        NSLayoutConstraint.activate([
            camera.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            camera.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            camera.topAnchor.constraint(equalTo: view.topAnchor),
            camera.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        var configuration = CameraConfiguration()
        configuration.scanBarcode = true
        configuration.allowedBarcodeTypes = [.qr, .ean13]
        configuration.showFrame = true
        camera.configuration = configuration
        camera.onReadCode = { code in
            print(code.codeStringValue, code.codeFormat.rawValue)
        }
        camera.onError = { error in
            print(error.localizedDescription)
        }
    }

    func takePhoto() {
        Task { @MainActor in
            do {
                let photo = try await camera.capture()
                print(photo.uri, photo.width, photo.height, photo.size)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
}
```

Call the UIKit API on the main thread. Attaching the view to a window starts the camera and requests permission when needed. Removing it stops the session. Use `start()` and `stop()` to manage a view that stays attached while another screen covers it. The view also handles application background and foreground transitions. Permission denial is reported through `onError`. `isRunning` describes the requested state; hardware startup is asynchronous and `capture()` checks readiness. If setup fails, call `stop()` followed by `start()` to retry.

To request permission before presenting the view, read `CameraAuthorization.status` and call `try await CameraAuthorization.requestAccess()`. A denied or restricted request returns `false`; a missing usage description throws `CameraError.missingUsageDescription`.

`capture()` returns a typed `CapturedPhoto` containing `url`, `uri`, `name`, `size`, `width`, `height`, and the source-compatible empty `thumb`. The image is not cropped to the scan frame or ratio guide. Concurrent capture requests are rejected while a capture is pending.

## Optional SwiftUI adapter

```swift
import NativeCameraKit
import SwiftUI

struct CameraScreen: View {
    @State private var camera = CameraController()

    var body: some View {
        CameraPreview(controller: camera)
    }
}
```

UIKit owns the preview and interactions. The adapter manages view attachment and exposes the same configuration and typed events through its controller.

## Feature parity

See [PARITY.md](PARITY.md) for the source-to-native mapping, defaults, intentional differences, and device acceptance checklist.

## Validation

From the repository root:

```sh
xcodebuild -scheme NativeCameraKit \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

xcodebuild -project NativeCameraKit/Example/CameraKitDemo.xcodeproj \
  -scheme CameraKitDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

xcodebuild -project NativeCameraKit/Example/CameraKitDemo.xcodeproj \
  -scheme CameraKitDemo -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Choose an installed simulator if the named device is unavailable. Simulator tests cover API, layout, lifecycle, JPEG capture, Vision face inference on a public-domain image, and the UIKit flows. They do not prove sensor input, live barcode or face detection, torch, autofocus, or hardware-button behavior. See [VALIDATION.md](VALIDATION.md) for recorded results and follow the device checklist before a production release.

## License and source

MIT, under the repository [LICENSE](../LICENSE). The camera engine and view helpers are adapted from the existing iOS implementation. Source file headers retain attribution where present.

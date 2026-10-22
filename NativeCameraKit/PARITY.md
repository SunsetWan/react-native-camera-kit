# iOS feature parity

Baseline: `ios/ReactNativeCameraKit`, `src/Camera.ios.tsx`, `src/CameraProps.ts`, and `src/types.ts` at v18.0.1 (`a2a81ce`). The implementation targets iOS 18 or later. UIKit is the primary API and example UI.

| Source feature | Native API | Behavior |
| --- | --- | --- |
| Front/back camera | `configuration.cameraType` | AVFoundation camera selection and camera switch |
| Preview scaling | `resizeMode` | `.contain` / `.cover` |
| Flash and torch | `flashMode`, `torchMode` | Auto/on/off flash; on/off torch where supported |
| Tap focus/exposure | `focusMode` | Focus indicator and native focus/exposure point |
| Focus reset | `resetFocusTimeout`, `resetFocusWhenMotionDetected` | Millisecond timeout and subject-area change reset |
| Pinch/controlled zoom | `zoomMode`, `zoom`, `maxZoom`, `onZoom` | Camera-relative zoom with hardware bounds; an explicit zoom owns the applied value |
| Permission | `CameraAuthorization.status`, `requestAccess()` | Native authorization status and explicit permission request |
| Capture | `capture()` | JPEG cache URL, byte size, name, pixel dimensions, empty thumbnail field |
| Capture quality | `maxPhotoQualityPrioritization` | `.speed`, `.balanced`, `.quality` |
| Deferred start | `iOsDeferredStart` | Availability and hardware gated on iOS 26+ |
| Barcode/QR scanner | `scanBarcode`, `allowedBarcodeTypes`, `onReadCode` | Typed format and decoded string; empty allowlist means all supported formats |
| Scanner frame | `showFrame`, `barcodeFrameSize` | Centered scan region and shaded surrounding area |
| Scanner appearance | `frameColor`, `laserColor` | Native frame and animated scan line |
| Scan timing | `scanThrottleDelay` | Millisecond event throttle |
| Ratio guide | `ratioOverlay`, `ratioOverlayColor` | Guide only; capture is not cropped |
| Faces | `faceDetectionEnabled`, `faceDetectionThrottleMs`, `onFaceDetected` | Apple Vision rectangles, numeric IDs, yaw/pitch/roll in degrees, normalized top-left bounds |
| Device orientation | `onOrientationChange` | Portrait=0, landscape-left=1, upside-down=2, landscape-right=3 |
| Capture hardware | `onCaptureButtonPressIn`, `onCaptureButtonPressOut` | Native `AVCaptureEventInteraction` events |
| Simulator | Native sample preview/capture | Animated balloons, randomized camera/resize scene, control labels, timestamped JPEG; no remote asset or permission needed |
| Styling/ref | UIKit layout / `CameraView` | UIKit constraints, properties, and typed async methods |

## Defaults and intentional differences

- Defaults follow the effective iOS API, including its TypeScript wrapper: preview `.contain`, frame white, ratio mask black at 30% opacity, and motion-based focus reset `true`. The wrapper enables motion reset even though the internal Swift property starts as `false`.
- Flash defaults to `.auto`, torch `.off`, focus and pinch `.on`, quality `.balanced`, barcode and face detection off, scan delay 2000 ms, face throttle 100 ms, and focus timeout 0. Deferred start defaults to enabled on supported systems.
- Permission handling is native. The view requests camera access and reports denial. `CameraAuthorization` also supports preflight checks and explicit requests. The original iOS wrapper incorrectly forwards its request method to the status check; the native request method prompts when appropriate. No separate React Native permissions package is required.
- Typed errors replace silent initialization failure; capture before readiness and overlapping requests fail explicitly.
- Detaching a view preserves its reusable session configuration. The session stops in the background and can restart in the foreground. Session configuration and running state changes use a serial queue, as required by [AVFoundation](https://developer.apple.com/documentation/avfoundation/avcapturesession).
- Invalid ratios, non-finite zoom, and scan frames larger than the view are handled defensively. Ratio strings retain the source height:width convention (`16:9` produces a portrait guide); the guide now stays centered with the requested ratio in both portrait and landscape.
- Session graph changes wait for outstanding native captures to finish. A stopped capture resolves once, while its native delegate stays alive until AVFoundation completes the request.
- Face detection uses unrotated, unmirrored sample buffers and explicit Vision orientation, then maps results into the preview. This also handles camera switches and contain/cover layouts.
- The simulator preserves the animated balloon scene, scene randomization on camera or resize changes, control labels, and timestamped preview snapshots. JPEG dimensions match the displayed preview at screen scale, with a 480 × 640 fallback for an unattached zero-size view. Live barcode/face detection is not simulated.
- Android-only `shutterPhotoSound`, ML Kit installation events, and Android output-path behavior are not iOS APIs. iOS controls shutter sound. This port adds no video recording because the source public API has none.
- Face IDs are per-frame indices, matching the source; they are not persistent identity or tracking IDs.
- Existing React Native and Android source is unchanged. This is an additive package and UIKit application, not a replacement npm entry point.

## Example parity

The UIKit home screen follows `example/src/App.tsx`: Camera, Barcode / QR, and Mount Stress Test. Camera includes a five-photo burst and timing median, a 1× reset, and a 500 ms random-zoom stress mode. The scanner matches the QR/EAN-13 filter, 300 × 150 frame, red scan line, 3:4 preview, vibration, and two-second result clear. The mount test supports an editable interval and manual stop. UIKit navigation and a settings table replace React Native controls.

## Physical-device acceptance

These checks require a real device and are not implied by a passing simulator test.

- [ ] Grant, deny, and restore camera permission in Settings; confirm no blank silent failure.
- [ ] Open and close the camera repeatedly; background/foreground it; interrupt it with another camera user and recover.
- [ ] Switch front/back cameras; inspect preview and JPEG orientation in all four device orientations.
- [ ] Pinch from minimum to maximum; apply controlled zoom and a maximum; switch cameras after zooming.
- [ ] Exercise flash auto/on/off and torch on/off on supported cameras.
- [ ] Tap at each preview corner, change the subject, and verify timeout/motion focus reset.
- [ ] Capture repeatedly at every quality setting; inspect JPEG dimensions and cache URLs.
- [ ] Scan QR and supported barcodes inside/outside the frame; change filters, frame size, and throttle while running.
- [ ] Detect zero/one/multiple faces with front and rear cameras, contain/cover, rotation, and different aspect ratios; verify overlay alignment and angle signs.
- [ ] Press and release a supported hardware capture button; ensure the application captures once on release.
- [ ] On iOS 26+, compare startup and first capture with deferred start on/off.

## Evidence boundary

A simulator JPEG is evidence for file output and app flow, not camera image quality or sensor behavior. A device-target build is compile evidence, not a device test. Record physical-device results separately before claiming full hardware parity. Recorded simulator, Vision fixture, and build results are in [VALIDATION.md](VALIDATION.md).

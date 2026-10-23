# Native validation

Baseline: React Native Camera Kit v18.0.1 (`a2a81ce`). Target: iOS 18+, UIKit first. Validation date: 2026-10-24.

## Automated checks

| Check | Environment | Result |
| --- | --- | --- |
| Swift package | Xcode 26.6, iOS 18.6 Simulator | 52 tests passed, 0 failed |
| Example behavior tests | iOS 18.6 Simulator | 7 passed, 0 failed |
| UIKit UI tests | iOS 18.6 Simulator | 7 passed, 0 failed |
| Hardware test on simulator | iOS 18.6 Simulator | 1 skipped, as required |
| Native SwiftLint | Repository rule thresholds, native paths | 0 errors; 29 style warnings |
| Signed device build | Xcode 26.6, Apple Development signing | Passed |
| Installation | iPhone 17 Pro Max, iOS 27.0.1 | Passed |
| Concurrent hardware capture | Same physical device | 1 passed, 0 failed; three JPEGs decoded and checked |

The package suite covers effective source defaults, all iOS barcode mappings, sensor-angle and mirroring transforms, scan throttling, lifecycle and background recovery, concurrent capture and cancellation, JPEG contents and dimensions, view release, source scan/ratio geometry, controlled and uncontrolled zoom, queued capture configuration, focus timeout and stale callbacks, optional detection callbacks, face projection, Vision inference, and snapshot brightness during a preceding shutter fade. New parity cases were first run against the previous implementation and failed before the fixes.

Four tests execute Vision's face rectangle model against a public-domain portrait and a blank image. They verify face bounds, mirrored coordinates, empty results, and throttled frames. The tests explicitly select the model's supported CPU compute device because simulator acceleration can be unavailable. Production keeps Vision's default compute-device selection. This is inference evidence, not evidence for a live camera feed.

The example tests check photo/scanner presets, the 50 ms photo face throttle, full-resolution 10x photo inspection, orientation icon transforms, and positive stress intervals. UI tests cover two five-photo bursts, settings persistence, scanner presets, mount/stop navigation, intervals below 100 ms, and pinch zoom after controlled zoom is disabled. An iOS 18 accessibility locator failed while the correct 50 ms value was visible; the test now locates the settings row by its title. The complete final run passed. Screenshots are retained in the result bundle.

The device build reports five deprecation warnings from the isolated cardinal-orientation compatibility helper. Its fixed-angle replacement was incorrect for the iPhone 17 front sensor. See [PARITY.md](PARITY.md#defaults-and-intentional-differences) for the reason this helper remains.

## Reproduce

Run the commands in [README.md](README.md#validation). Use an installed iOS 18 or later simulator. The `Native Swift` GitHub Actions workflow runs the package suite, UIKit tests, and an unsigned device build, and uploads the result bundles.

For a connected physical device, set a development team and device identifier through local build settings. The example contains no account-specific signing settings.

After granting camera access, run `HardwareCaptureIntegrationTests/testConcurrentCapturesProduceIndependentJPEGs` from the example test target on an unlocked iPhone or iPad. The test waits for the session, captures one warmup JPEG, starts two overlapping public `capture()` calls, and checks distinct URLs, file byte counts, JPEG type, decoded pixel dimensions, and overlapping request intervals. It retains the three JPEGs and a JSON timeline as test attachments, then removes its cache files. It skips on simulators and devices without camera permission.

## Physical-device results

The device was unlocked and available for this run. Results below belong to the updated build unless marked as the previous revision.

| Scenario | Result | Evidence |
| --- | --- | --- |
| Front portrait preview and JPEG | Passed | The previous revision showed both sideways by 90 degrees. The updated preview and five-photo burst are upright; the inspected JPEG is 4032 x 3024. |
| Concurrent rear captures | Passed | Both requests started at 1.1357 s after warmup start; they finished at 1.2101 s and 1.3623 s. Each decoded to 4032 x 3024. Distinct files contained 1,044,834 and 1,047,848 bytes. |
| QR through the live camera | Passed | The scanner returned `qr: NativeCameraKit-QR-20261024` from a screen target. |
| EAN-13 through the live camera | Passed | The scanner returned `ean-13: 5901234123457` from a screen target. |
| Rear face detection | Passed for one portrait | The live camera detected one face in a public-domain NASA portrait. The overlay matched the face; count, angles, facing state, and normalized bounds were visible. |
| Front landscape face events | Passed for event delivery | The live view emitted one face with angle and bounds fields, then zero after the subject moved away. The automation tool distorted landscape screenshots, so overlay alignment and icon rotation were not accepted from this check. No photo was captured. |
| Tap-focus indicator | Passed | A tap displayed the focus box over the live scanner preview. This does not measure focus accuracy. |
| Rear torch and background recovery | Passed | Torch off/on/off changed scene illumination. Returning home and reactivating the running app restored preview and a five-photo burst. |
| Camera permission grant | Passed on previous revision `d480026` | Granting the system camera prompt showed a live preview. |
| Two-minute mount stress | Passed on previous revision `d480026` | 66 mounts in 131 seconds, then a normal manual stop. This was not a measured memory-leak test. |

The native application was checked against the source behavior. The React Native application was not run side by side on the device. Capture times are observations, not a controlled performance comparison.

## Remaining hardware matrix

The full [device checklist](PARITY.md#physical-device-acceptance) remains broader than these checks: permission denial/restoration, interruptions by another camera user, all four orientations, front/rear multi-face angle and bounds checks, every barcode format and filter transition, autofocus accuracy and motion reset, all quality/flash modes, hardware capture buttons, and deferred-start timing need dedicated coverage. Passing the source audit and the recorded checks does not establish every combination on every camera model.

Simulator captures prove file output and application flow. They do not prove sensor quality, live barcode/face detection, autofocus, torch, camera orientation, capture-button input, or deferred-start timing. An unsigned or signed device build proves compilation; installation proves deployment.

## Existing repository checks

The original React Native and Android source was not changed. Existing fork workflows fail independently of the native package: the Linux lint job invokes CocoaPods without Xcode; the Android bootstrap cannot find Bundler; the React Native iOS build reports `fmt` constant-expression errors. The dedicated native workflow is the relevant build and test check for this additive package.

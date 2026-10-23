# Native validation

Baseline: React Native Camera Kit v18.0.1 (`a2a81ce`). Target: iOS 18+, UIKit first. Validation date: 2026-10-24.

## Automated checks

| Check | Environment | Result |
| --- | --- | --- |
| Swift package | Xcode 26.6, iOS 18.6 Simulator | 54 tests passed, 0 failed |
| Example behavior tests | iOS 18.6 Simulator | 11 passed, 0 failed |
| UIKit UI tests | iOS 18.6 Simulator | 7 passed, 0 failed |
| Hardware checks on simulator | iOS 18.6 Simulator | 14 skipped, as required |
| Native SwiftLint | Repository rule thresholds, native paths | 0 errors; 36 style warnings |
| Signed device build | Xcode 26.6, Apple Development signing | Passed |
| Installation | iPhone 17 Pro Max, iOS 27.0.1 | Passed |
| Hardware capture matrix | Same physical device | 12 passed, 0 skipped, 0 failed |
| Synthesized hardware buttons | Same physical device | 1 passed, 0 skipped, 0 failed; all three buttons checked |

The package suite covers effective source defaults, all iOS barcode mappings, sensor-angle and mirroring transforms, scan throttling, lifecycle and background recovery, concurrent capture and cancellation, JPEG contents and dimensions, view release, source scan/ratio geometry, controlled and uncontrolled zoom, queued capture configuration, focus timeout and stale callbacks, optional detection callbacks, face projection, Vision inference, and snapshot brightness during a preceding shutter fade. New parity cases were first run against the previous implementation and failed before the fixes.

Six tests execute Vision's face rectangle model against a public-domain portrait and a blank image. They verify face bounds, mirrored coordinates, empty results, and throttled frames. Two orientation tests add 16 cases with an off-center portrait on a non-square image: four sensor rotations with and without mirroring, and four rotated subjects in a fixed preview with and without mirroring. The sensor matrix checks bounds and pose invariance. The locked-preview matrix checks bounds and roll, and requires finite yaw and pitch. The tests explicitly select the model's supported CPU compute device because simulator acceleration can be unavailable. Production keeps Vision's default compute-device selection. This is inference evidence, not evidence for a live camera feed.

The example tests check photo/scanner presets, the 50 ms photo face throttle, full-resolution 10x photo inspection, orientation icon transforms, positive stress intervals, landscape layout, state preservation across rotation, and hardware press-in without capture or persistent dimming. UI tests cover two five-photo bursts, settings persistence, scanner presets, mount/stop navigation, intervals below 100 ms, and pinch zoom after controlled zoom is disabled. An iOS 18 accessibility locator failed while the correct 50 ms value was visible; the test now locates the settings row by its title. The complete final run passed. Screenshots are retained in the result bundle.

The device build reports five deprecation warnings from the isolated cardinal-orientation compatibility helper. Its fixed-angle replacement was incorrect for the iPhone 17 front sensor. See [PARITY.md](PARITY.md#defaults-and-intentional-differences) for the reason this helper remains.

## Reproduce

Run the commands in [README.md](README.md#validation). Use an installed iOS 18 or later simulator. The `Native Swift` GitHub Actions workflow runs the package suite, UIKit tests, and an unsigned device build, and uploads the result bundles.

For a connected physical device, set a development team and device identifier through local build settings. The example contains no account-specific signing settings.

After granting camera access, run `HardwareCaptureIntegrationTests/testConcurrentCapturesProduceIndependentJPEGs` from the example test target on an unlocked iPhone or iPad. The test waits for the session, captures one warmup JPEG, starts two overlapping public `capture()` calls, and checks distinct URLs, file byte counts, JPEG type, decoded pixel dimensions, and overlapping request intervals. It retains the three JPEGs and a JSON timeline as test attachments, then removes its cache files. It skips on simulators and devices without camera permission.

Run the complete `HardwareCaptureIntegrationTests` class for the 12-case matrix: six front/back quality combinations, three rear flash modes, two deferred-start settings, and concurrent capture. The new single-capture fixtures wait for foreground activation, inspect the active camera and photo output, and confirm that the session stops. Unsupported hardware features skip explicitly. Each case records configuration, decoded JPEG metadata, and timing in local result attachments.

Run `HardwareAcceptanceTests/testHardwareShutterButtonsTriggerOneBurstEach` on a device with volume and Camera Control buttons. This test sends one XCTest button press at a time. On this host, XCTest application launch failed before the test could interact with the app; launching with `devicectl` and opening Camera first allowed the same test to run against the foreground app. Run `testCurrentCameraPreviewForManualReview` to retain the current raw screenshot and accessibility hierarchy without relaunching or resetting the camera. Its success only confirms evidence collection; face alignment and orientation require visual review. Keep physical-device result bundles private because their attachments can contain personal photographs.

## Physical-device results

Follow-up testing found a photo-screen layout defect: a 956 x 440 point landscape window left the preview only about 105 points tall. The photo screen now places capture controls beside the preview in landscape. The matching layout regression has a 530 x 269 point preview, and the physical device exposes 530 x 272 points. The same camera and view hierarchy survive rotation. A separate review removed extra press-in dimming that could remain after a cancelled hardware event; the source example has no such visual state.

The device was unlocked and available for this run. Results below belong to the updated build unless marked as the previous revision.

| Scenario | Result | Evidence |
| --- | --- | --- |
| Front portrait preview and JPEG | Passed | The previous revision showed both sideways by 90 degrees. The updated preview and five-photo burst are upright; the inspected JPEG is 4032 x 3024. |
| Rear JPEG orientation in all four directions | Passed on `4814dce` | Four physical poses each saved exactly five JPEGs. Representative files decoded to 4032 x 3024; EXIF orientation was 6, 1, 3, and 8 for portrait, top edge left, top edge right, and upside down. All four displayed upright with EXIF applied. |
| Physical capture buttons | Passed | Human presses of volume up, volume down, and Camera Control each produced exactly one five-photo burst. Camera Control did not leave the application. Front-camera follow-up repeats all three buttons on the updated build. The final upside-down step produced three groups while the user could not confirm the press count; that step is used only for orientation and face alignment. |
| Concurrent rear captures | Passed again in the 12-case matrix | Two overlapping requests returned distinct JPEG URLs with valid byte counts and decoded dimensions of 4032 x 3024. |
| Front/back quality settings | Passed | All six combinations of camera and speed/balanced/quality produced valid 4032 x 3024 JPEGs across repeated matrix runs. Tests verified the actual input position and output quality setting. This does not rank image quality. |
| Rear flash auto/off/on | Passed | All three supported modes produced valid JPEGs. EXIF Flash was 24, 16, and 9 respectively; On fired and Off did not. Auto did not fire in this scene. Bright/dark switching thresholds were not tested. |
| Deferred start off/on | Passed on supported output | The actual photo output reported the requested setting. Both cases produced valid first JPEGs. Startup and capture observations are listed below; they do not prove a speed improvement. |
| QR through the live camera | Passed | The scanner returned `qr: NativeCameraKit-QR-20261024` from a screen target. |
| EAN-13 through the live camera | Passed | The scanner returned `ean-13: 5901234123457` from a screen target. |
| Rear face detection | Passed for one portrait | The live camera detected one face in a public-domain NASA portrait. The overlay matched the face; count, angles, facing state, and normalized bounds were visible. |
| Front face bounds and JPEGs in four physical orientations | Passed for one live face | Portrait, top edge left, top edge right, and upside-down poses were inspected with raw XCTest screenshots. The face box matched the face in all four. Representative JPEGs were 4032 x 3024 with EXIF 6, 3, 1, and 8 and displayed upright. Mirrored preview and non-mirrored output were consistent. The upside-down pose retained a landscape interface; its overlay remained aligned and icons followed physical orientation relative to that interface. |
| Synthesized hardware capture buttons | Passed | One XCTest press each of volume up, volume down, and Camera Control increased the counter by exactly five; the shutter became ready and remained idle for a 1.5-second duplicate-event check. This complements, but does not replace, the human presses. |
| Tap-focus indicator | Passed | A tap displayed the focus box over the live scanner preview. This does not measure focus accuracy. |
| Rear torch and background recovery | Passed | Torch off/on/off changed scene illumination. Returning home and reactivating the running app restored preview and a five-photo burst. |
| Camera permission grant | Passed on previous revision `d480026` | Granting the system camera prompt showed a live preview. |
| Camera permission denial and restoration | Passed | Turning access off in Settings showed an explicit denied/restricted error. Restoring access allowed a five-photo burst. Camera access was left enabled. |
| Return after system Camera use | Passed | The system Camera showed its live viewfinder. Returning to the running example restored capture and completed a five-photo burst. This does not prove that the session's interruption-notification branch ran. |
| Two-minute mount stress | Passed on previous revision `d480026` | 66 mounts in 131 seconds, then a normal manual stop. This was not a measured memory-leak test. |

The deferred-start samples used a new rear-camera view, speed priority, and flash off. Startup means view attachment through first JPEG completion; capture means the public capture call through completion.

| Deferred start | Startup to first JPEG | Capture call to JPEG |
| --- | --- | --- |
| Off | 1008.8 ms | 559.1 ms |
| On | 1516.2 ms | 1289.4 ms |

These are single, uncontrolled samples on one device. Session-start notification and test scheduling affect the intervals; they do not measure preview readiness or establish a performance regression or gain.

An earlier matrix run completed its JPEGs but timed out while waiting only for a stop notification in the deferred-start case. Three focused repeats passed. The final fixture checks actual `isRunning == false` within five seconds and records the notification separately. All 11 new fixtures stopped and received their stop notification in the final 12-case run. No production session defect was established by the earlier timeout.

The native application was checked against the source behavior. The React Native application was not run side by side on the device. Capture times are observations, not a controlled performance comparison.

## Remaining hardware matrix

The full [device checklist](PARITY.md#physical-device-acceptance) remains broader than these checks: confirmed session-interruption recovery, other sensor models, the full physical zoom matrix, front/rear multi-face angle and bounds checks, every barcode format and filter transition, autofocus accuracy and motion reset, front flash support and lighting extremes, held/cancelled hardware-button interactions, and controlled deferred-start benchmarks need dedicated coverage. Passing the source audit and the recorded checks does not establish every combination on every camera model.

Simulator captures prove file output and application flow. They do not prove sensor quality, live barcode/face detection, autofocus, torch, camera orientation, capture-button input, or deferred-start timing. An unsigned or signed device build proves compilation; installation proves deployment.

## Existing repository checks

The original React Native and Android source was not changed. Existing fork workflows fail independently of the native package: the Linux lint job invokes CocoaPods without Xcode; the Android bootstrap cannot find Bundler; the React Native iOS build reports `fmt` constant-expression errors. The dedicated native workflow is the relevant build and test check for this additive package.

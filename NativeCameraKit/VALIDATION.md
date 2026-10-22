# Native validation

Baseline: React Native Camera Kit v18.0.1 (`a2a81ce`). Target: iOS 18+, UIKit first. Validation date: 2026-10-23.

## Automated checks

| Check | Environment | Result |
| --- | --- | --- |
| Swift package | Xcode 26.6, iOS 18.6 Simulator | 41 tests passed, 0 failed |
| UIKit application | iOS 18.6 Simulator | 4 tests passed, 0 failed; capture rerun passed after the final snapshot fix |
| Native SwiftLint | Repository rule thresholds, native paths | 0 errors; 25 style warnings |
| Device target build | Xcode 26.6, generic iOS, signing disabled | Passed |
| Signed device build | Xcode 26.6, Apple Development signing | Passed |
| Installation | iPhone 17 Pro Max, iOS 27.0.1 | Passed |

The package suite covers configuration defaults, all iOS barcode mappings, orientation values, scan throttling, lifecycle and background recovery, capture failure and overlap, exactly-once capture cancellation, JPEG contents and dimensions, view release, scan and ratio geometry, controlled zoom, queued capture configuration, focus timeout and stale callbacks, optional detection callbacks, face projection, Vision inference, and snapshot brightness during a preceding shutter fade.

Four tests execute Vision's face rectangle model against a public-domain portrait and a blank image. They verify face bounds, mirrored coordinates, empty results, and throttled frames. The tests explicitly select the model's supported CPU compute device because simulator acceleration can be unavailable. Production keeps Vision's default compute-device selection. This is inference evidence, not evidence for a live camera feed.

The UIKit tests cover two five-photo bursts and the photo viewer, settings persistence, scanner presets and navigation, and repeated camera mounting with a manual stop. Screenshots are retained in the test result bundle.

## Reproduce

Run the commands in [README.md](README.md#validation). Use an installed iOS 18 or later simulator. The `Native Swift` GitHub Actions workflow runs the package suite, UIKit tests, and an unsigned device build, and uploads the result bundles.

For a connected physical device, set a development team and device identifier through local build settings. The example contains no account-specific signing settings.

## Hardware boundary

Installation passed, but launching the app timed out while the device reported that a passcode was required. No physical capture or sensor result is claimed from that attempt. Continue with the [device checklist](PARITY.md#physical-device-acceptance) on an unlocked device.

Simulator captures prove file output and application flow. They do not prove sensor quality, live barcode/face detection, autofocus, torch, camera orientation, capture-button input, or deferred-start timing. An unsigned or signed device build proves compilation; installation proves deployment.

## Existing repository checks

The original React Native and Android source was not changed. Existing fork workflows fail independently of the native package: the Linux lint job invokes CocoaPods without Xcode; the Android bootstrap cannot find Bundler; the React Native iOS build reports `fmt` constant-expression errors. The dedicated native workflow is the relevant build and test check for this additive package.

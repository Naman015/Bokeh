# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Bokeh is a single-target iOS app (Xcode project at `Bokeh.xcodeproj/`, sources flat under `Bokeh/`) built for the Swift Student Challenge. It uses the camera + the Vision framework to "lift" one cluttered object at a time, times the user putting it away, and journals it for later recall via Core Spotlight. Target audience is ADHD/autism users who get overwhelmed by visual clutter — the privacy story (everything stays on-device) is load-bearing for the pitch (see `HowItWorksView.swift`).

Originally a Swift Playgrounds app (`Bokeh.swiftpm/`), now migrated to a normal Xcode project. Build settings: `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `IPHONEOS_DEPLOYMENT_TARGET = 18.2`, `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad). The target uses `PBXFileSystemSynchronizedRootGroup` — every file under `Bokeh/` is auto-bundled, so just dropping a file in the folder adds it to the build. `Bokeh/Info.plist` is the one membership exception (used via `INFOPLIST_FILE` instead of being copied as a resource); if you add other files Xcode shouldn't bundle, extend that exception set in `project.pbxproj`.

## Build & run

- Open `Bokeh.xcodeproj` in Xcode 16+ and run on a physical iPhone/iPad — the simulator has no camera, so almost nothing in the app works there.
- No CLI build/lint/test rig is wired up. For diagnostics: `xcodebuild -project Bokeh.xcodeproj -scheme Bokeh -destination 'generic/platform=iOS' build`.
- **Long-press anywhere on the camera screen at runtime** to toggle Vision debug mode (overlays mask, normalized bbox, EXIF orientation used, classifier label/confidence; lets you re-run with a forced orientation or a synthetic test image).

## Architecture

### State machine

`ContentView.swift` is the whole router: a switch over `AppState` (`scanning` / `success`) gated by `@AppStorage("hasSeenOnboarding")` and `manager.permissionGranted`, with `FocusLogView` and `HowItWorksView` as sheets. There is no coordinator — just `@State`. Spotlight deep-links are handled here in `.onContinueUserActivity(CSSearchableItemActionType)`, which force-sets `hasSeenOnboarding = true` and routes into the Focus Log focused on the tapped item.

### Vision pipeline (the only non-trivial subsystem)

`CameraManager.swift` → `MagicFocusView.swift`'s `SubjectLifter`:

1. `AVCaptureSession` runs `.hd1280x720` BGRA frames on a private `videoQueue`, back camera preferred. Frame delivery is a **one-shot** callback installed via `setCaptureFrameCallback` — the next frame fires the callback once and clears it. Concurrency here is delicate: the pipeline's `CVPixelBuffer` is **copied on the capture queue** (`copyPixelBuffer`) before the captureLock-guarded handoff to main. Do not refactor this to pass the original buffer across queues — it causes `FigSharedMemPool` use-after-free.
2. `SubjectLifter.lift` runs `VNGenerateForegroundInstanceMaskRequest` → masks the CIImage via `CIFilter.blendWithMask` → re-runs `VNClassifyImageRequest` on the **foreground cutout only** so the classifier sees the object, not the scene. A small denylist (`structure`, `artifact`, `object`, `container`, …) drops generic labels.
3. **Orientation is fragile.** If the captured buffer is already portrait-shaped (`h > w`, e.g. when the connection rotated output for us), Vision gets `.up`; otherwise it uses the interface-orientation-derived EXIF code. After cutout, pixels are **physically rotated** with `rotatePixels` (CGContext transform) before being wrapped in `UIImage(orientation: .up)`, because PNG encoding ignores `UIImage.imageOrientation` — without this the saved Focus Log thumbnails would be sideways. Debug mode reports which orientation was used.
4. `SubjectLifter.prewarmVisionModel()` is fired on the onboarding "Get Started" tap to warm the ML model and hide first-lift latency.

### Persistence

`ClearLog.swift` / `LogManager`:

- Cutout PNGs + a `manifest.json` are written to `Application Support/BokehHistory/`. There is a one-shot migration on init that moves a legacy `Documents/BokehHistory/` over if found — keep it; older test builds still have data in the old path.
- `ClearLog.originalImage` is deliberately omitted from the `CodingKeys` — it's an in-memory-only sticker; persistent images live as separate PNGs keyed by `filename`.
- Every `add`/`update`/`remove`/`clearAll` mirrors into `SpotlightManager`, which writes a `CSSearchableItem` per entry (title=label, description=location+date, JPEG thumbnail). The README's privacy claim that journal content isn't in Spotlight is *technically* contradicted by this — the index does hold title/description/thumbnail. Don't broaden the indexed fields without checking the README copy.

### Search

`SmartSearchEngine.swift` uses `NLTagger` to extract nouns from queries like "Where are my keys?" and matches them against `label` + `location`. If no nouns are extracted (or the query is short) it falls back to substring contains. The Focus Log's `.searchable` placeholder mirrors this conversational style.

## Conventions

- Design tokens live in `Theme.swift` (`Color.theme.bokehTeal`, `.bokehFont(_:weight:)`, `.bokehCardStyle()`) and `AppLayoutConstants.swift` (`minTouchTarget = 44`, padding helpers parameterized by `horizontalSizeClass`, `defaultLocationTags`). `ContentView.swift` and a couple of older views still keep **duplicate hardcoded** copies (`Self.teal`, `Self.titleColor`) — prefer the centralized ones for new code.
- All interactive controls use `AppLayoutConstants.minTouchTarget` (44pt) and `ScaleButtonStyle` / `OpacityButtonStyle` from `BokehButtonStyles.swift` for press feedback.
- Typography is SF Pro Rounded with Dynamic Type via `.bokehFont(_:weight:)`. Don't hand-roll `.font(.system(...))` unless there's a reason.
- The "no network, no analytics, no third-party SDKs" claim in `HowItWorksView` is part of the user-facing pitch — don't introduce any of these without also updating that copy.

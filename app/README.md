# ZeroLog app (iPhone + Apple Watch)

Built without a Mac: code is written on Windows, and **GitHub's Mac servers** build and test it on every push (`.github/workflows/app.yml`). Results: GitHub → repo → **Actions** tab.

| Folder / file | What it is |
|---|---|
| `Packages/ZeroLogCore/` | The app's brain, shared by phone and watch: the exercise database + the workout engine (Swift version of `core/engine.py`) + its tests. |
| `ZeroLog/` | The iPhone app. For now, one screen: today's workout from the engine. |
| `ZeroLogWatch/` | The Watch app. For now, one card: exercise, reps, "80 kg?", and the ✓ button. |
| `Shared/` | Small files both apps use (the plate-blue colour, sample gym + history). |
| `project.yml` | Recipe for the Xcode project. XcodeGen turns it into `ZeroLog.xcodeproj` on the build server, so the project file is never hand-edited or committed. |

## Rules
- The exercise database exists in two places (`core/data/` for Python, `Packages/ZeroLogCore/Sources/ZeroLogCore/Resources/` for Swift). The build **fails if they differ**, so edit one and copy it to the other.
- Engine rules live in both `core/engine.py` and `Engine.swift`. Change both, and keep both test files matching.
- Screens use sample data (`Shared/SampleData.swift`) until saved sessions and HealthKit are added.

## Running it on your own iPhone + Watch
Not possible yet. It needs the Apple Developer account ($99/yr, from Nov 10, dad approves). Then the build server can sign the app and send it to TestFlight.
On a Mac it would be: `brew install xcodegen`, `xcodegen generate`, open `ZeroLog.xcodeproj`, press Run.

# ZeroLog app (iPhone + Apple Watch)

Built without a Mac: code is written on Windows, and **GitHub's Mac servers** build and test it on every push (`.github/workflows/app.yml`). Results: GitHub → repo → **Actions** tab.

| Folder / file | What it is |
|---|---|
| `Packages/ZeroLogCore/` | The app's brain, shared by phone and watch: the exercise database + the workout engine + its 36 tests. Foundation-only, so it builds and tests on Windows and Linux with no Mac. |
| `ZeroLog/` | The iPhone app. For now, one screen: today's workout from the engine. |
| `ZeroLogWatch/` | The Watch app. For now, one card: exercise, reps, "80 kg?", and the ✓ button. |
| `Shared/` | Small files both apps use (the plate-blue colour, sample gym + history). |
| `project.yml` | Recipe for the Xcode project. XcodeGen turns it into `ZeroLog.xcodeproj` on the build server, so the project file is never hand-edited or committed. |

## Rules
- The exercise database lives in exactly one place: `Packages/ZeroLogCore/Sources/ZeroLogCore/Resources/exercises.json`.
- Engine rules live in exactly one place: `Engine.swift`. The Python mirror was retired on 2026-10-29 to stop the two drifting apart.
- Run the engine tests locally on Windows: `swift test --package-path app/Packages/ZeroLogCore` (~0.12s).
- Screens use sample data (`Shared/SampleData.swift`) until saved sessions and HealthKit are added.

## Running it on your own iPhone + Watch
Not possible yet. It needs the Apple Developer account ($99/yr, from Nov 10, dad approves). Then the build server can sign the app and send it to TestFlight.
On a Mac it would be: `brew install xcodegen`, `xcodegen generate`, open `ZeroLog.xcodeproj`, press Run.

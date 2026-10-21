# flowstate

A minimal, fully on-device focus app. Start a session, and everything except your allowed apps is blocked through iOS Screen Time.

## Stack
- Swift + SwiftUI (iOS 17+)
- SwiftData for local storage
- FamilyControls / ManagedSettings for app blocking
- Swift Charts for statistics
- XcodeGen: `project.yml` is the source of truth; `Flowstate.xcodeproj` is generated and git-ignored

## Develop in VS Code
1. Install the recommended extensions: **SweetPad** and **Swift**.
2. After adding/removing files or changing `project.yml`, run:
   ```sh
   xcodegen generate
   ```
3. Build and run on the simulator from SweetPad's sidebar (or `xcodebuild -scheme Flowstate -destination 'platform=iOS Simulator,name=iPhone 17' build`).

## Running on a real iPhone
There are two schemes:

| Scheme | Apple account | App blocking |
|---|---|---|
| `Flowstate Preview` | free | off |
| `Flowstate` | paid Developer Program | on |

App blocking (Screen Time) needs a paid account and never works in the simulator. The Preview build leaves it out so the rest of the app runs with a free account. Both builds share the same data on the phone.

1. Enable Developer Mode on the iPhone (Settings → Privacy & Security → Developer Mode), connect it, and unlock it.
2. In SweetPad pick the scheme and your iPhone, then run. Or from the terminal:
   ```sh
   xcodebuild -scheme "Flowstate Preview" -configuration Preview \
     -destination 'platform=iOS,id=<device id>' \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
   ```
3. With a free account, trust the developer on first launch: Settings → General → VPN & Device Management. Free installs expire after 7 days; run again to reinstall.

For the full build: put the paid team's ID in `DEVELOPMENT_TEAM` in `project.yml`, run `xcodegen generate`, and use the `Flowstate` scheme. Before App Store or TestFlight release, request the Family Controls distribution entitlement from Apple.

## Tests
```sh
# Logic: schedule windows, Pomodoro phases, unlock pricing, formatting
xcodebuild test -scheme Flowstate -only-testing:FlowstateTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Real Screen Time flow in the simulator (~2.5 min, grants Screen Time access on that simulator)
xcodebuild test -scheme Flowstate -only-testing:FlowstateUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Use a different simulator from the one you use day to day: the tests start the app there.

The UI test skips until Screen Time access is granted on that simulator. Apple asks for the passcode or Apple Account password, which a test can't type. So do this once by hand: sign in to an Apple Account in the simulator's Settings, open flowstate, tap Allow and finish the prompt.

## Blocking checklist for a real iPhone
The simulator covers the basics. These need the full build on a phone:
- [ ] During a session flowstate itself stays usable (you can end the session).
- [ ] Phone and incoming calls work during a session.
- [ ] Allowed apps, including whole allowed categories, stay open during a session.
- [ ] An earned-time unlock and a 5-minute emergency pass end on time with flowstate closed.
- [ ] Pomodoro breaks unlock and re-lock on time with flowstate closed.
- [ ] Date & Time can't be changed during a session or unlock.
- [ ] Turning off flowstate's Screen Time access in Settings removes all blocks, and the app notices.
- [ ] Blocks survive restarting the phone.

## Structure
```
Flowstate/
  App/        app entry point
  Models/     Subject, FocusSession (SwiftData), PomodoroConfig
  Services/   BlockingManager, SessionManager, EarnedTimeManager, notifications
  Views/      Focus, Subjects, Stats, Earned, Profile
  Utilities/  formatting, colors, comparisons, sample data
Shared/            Screen Time code used by the app and the extension
FlowstateMonitor/  extension that re-blocks apps in the background
```

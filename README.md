# flowstate

**A focus app that makes you earn your scrolling.**

Start a focus session and every app except the ones you allow is blocked. Focus, and you earn time for your distracting apps. Spend it when you want to scroll; when it's gone, they stay blocked until you've focused again.

flowstate runs completely on your phone. No account, no servers, no tracking.

## Why flowstate

Today everything is fighting for your attention. flowstate is for people who still value theirs.

As a student, I kept losing study sessions to social media. The only thing that worked was leaving my phone in another room. Then school went digital. Assignments, schedules, and class chats all lived on my phone, so it stayed within reach, and so did the distractions. My productive sessions slowly became unproductive ones.

So I built flowstate: a simple app that helps you stay focused and actually get work done, even with your phone right next to you. It blocks the apps that distract you and keeps the ones you actually need. Whether it's for work, personal growth, or just time away from your feed, flowstate protects your focus.

## How it works

### Focus sessions
Pick a subject (Math, Reading, a side project…) and tap **Start focus**. Until you end the session, every app is blocked except:
- the apps you allowed (a calculator, a dictionary, whatever your work needs),
- Phone and emergency calls, which are never blocked,
- apps in Settings → Screen Time → Always Allowed.

Ending a session takes a deliberate 1.5-second hold, so quitting on impulse is harder.


### Earning scrolling time
Every focus session earns minutes for your distracting apps (the ones you pick in **Earned time**, like Instagram or TikTok). Outside of an unlock, they stay blocked.

| Mode | Focus needed for 1 min of scrolling | 1 hour of focus earns | Most you can save up |
|---|---|---|---|
| Gentle | 2 min | 30 min | 90 min |
| Balanced (default) | 3 min | 20 min | 60 min |
| Strict | 4 min | 15 min | 30 min |

**Deep focus bonus.** Focus for 45 minutes or more in one go and that whole session earns 50% more. In Balanced, a 1-hour session earns 30 minutes instead of 20.

**Saving up has a limit.** Your balance stops growing at the mode's maximum, so you can't stockpile a whole day of scrolling. It doesn't reset at night: what you saved is still there tomorrow.

### Spending it
Unlock your distracting apps for 15, 30 or 60 minutes. The more you've scrolled today, the more each minute costs:

It's about how much you've already unlocked today, not the time of day:

| Scrolling unlocked today | Cost per minute | 15 minutes costs |
|---|---|---|
| first 30 min | 1 min of earned time | 15 min |
| next 30 min | 1.5 min | 22.5 min |
| after 1 hour | 2 min | 30 min |

The price resets at midnight. Finished early? **Lock now** gives back the time you didn't use.

Out of time but really need an app? You get **3 emergency passes a day**, 5 minutes each, free. Tap **earned** on the home screen and then **Use an emergency pass (5 min)**. The button shows up once you've chosen your distracting apps.

### No quick escapes
- Making things stricter works instantly. Making them easier (an easier mode, or removing a distracting app) takes **10 minutes**, and you can cancel in the meantime.
- While a session or an unlock is running, the phone's date and time can't be changed, so the clock can't be wound to stretch it.

### Stats
Time focused today, this week, month and year, with a streak, a calendar of every day, and comparisons like "that's 2.6 Harry Potter movie marathons". Each subject has its own page with a weekly goal, its history and a chart. Milestones go from your first hour up to 10,000 hours.

## Privacy
Everything stays on your phone. Apple's Screen Time keeps app choices private: flowstate never learns which apps you pick, only opaque tokens for blocking them.

---

# For developers

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
# Logic: schedule windows, unlock pricing, formatting
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
- [ ] Date & Time can't be changed during a session or unlock.
- [ ] Turning off flowstate's Screen Time access in Settings removes all blocks, and the app notices.
- [ ] Blocks survive restarting the phone.

## Structure
```
Flowstate/
  App/        app entry point
  Models/     Subject, FocusSession (SwiftData)
  Services/   BlockingManager, SessionManager, EarnedTimeManager
  Views/      Focus, Subjects, Stats, Earned, Profile
  Utilities/  formatting, colors, comparisons, sample data
Shared/            Screen Time code used by the app and the extension
FlowstateMonitor/  extension that re-blocks apps in the background
```

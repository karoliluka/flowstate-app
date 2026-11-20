# Earned scrolling time (switched off 2026-11-17)

"Study to earn scrolling" was taken out of flowstate on 17 November 2026, to be brought back later. Everything it needs is kept in this folder:

- `restore.patch` puts all of it back in one step (code, tests, README, project setup).
- `files/` holds readable copies of every file that was deleted, at their original paths.

## Restoring it

From the project folder:

```sh
git apply archive/earned-time/restore.patch
xcodegen generate
```

Then build, run the tests (`EarnedTimeRulesTests` and `ScheduleTests` come back too), and delete this `archive/earned-time` folder.

The patch removes the `RetiredEarnedShield` cleanup, which is only needed while the feature is switched off (see "What stayed behind" below).

**If the patch no longer applies** because the same lines have been changed since, apply what it can and fix the rest by hand:

```sh
git apply --reject archive/earned-time/restore.patch   # leaves *.rej files for the parts that didn't fit
```

Use the list below and the copies in `files/` as the guide.

**TestFlight:** builds can't include app blocking until Apple approves Family Controls on Edis's account. After restoring, `scripts/testflight.sh` again removes the `FlowstateMonitor` extension before signing, so App Store Connect doesn't send the ITMS-90897 warning. `scripts/setup-signing.py` still knows the monitor's app ID.

## What the feature did

Focus sessions earned minutes for the user's distracting apps (picked in **Earned time**, from the "earned" badge on the home screen). Outside an unlock, those apps were always blocked.

**Earning, by mode:**

| Mode | Focus per 1 min of scrolling | Cap on the balance |
|---|---|---|
| Gentle | 2 min | 90 min |
| Balanced (default) | 3 min | 60 min |
| Strict | 4 min | 30 min |

- **Deep focus:** a session of 45 minutes or more earned 1.5× for the whole session.
- **The balance:** it stopped growing at the cap and didn't reset at midnight.

**Spending:**
- **Unlocks:** 15, 30 or 60 minutes. Price per minute by how much was already unlocked that day: 1× up to 30 min, 1.5× up to 60 min, then 2×. The price reset at midnight.
- **Lock now:** ended an unlock early and refunded the unused part.
- **Emergency passes:** 3 a day, 5 minutes each, free.

**No quick escapes:**
- **10-minute cooldown on loosening:** switching to an easier mode or removing a distracting app waited 10 minutes and could be cancelled. Stricter changes applied at once.
- **Clock lock:** while an unlock ran, the date and time couldn't be changed.
- **Fail-closed:** an unlock only started if the re-block timer could be scheduled.

**How the blocking worked:**
- **Its own shield store:** distracting apps were shielded in their own `ManagedSettingsStore` named `earned`.
- **Re-blocking:** an unlock scheduled a `DeviceActivity` window (`flowstate.unlock`, or `flowstate.unlock.short` for windows under the 15-minute minimum, using `warningTime`). The `FlowstateMonitor` extension re-applied the shield when it ended, even with flowstate closed.
- **Shared settings:** the distracting-app selection lived in the App Group defaults (`distractingSelection`), so the extension could read it.

## What was removed

**Deleted files** (copies in `files/`):
- `Flowstate/Services/EarnedTimeManager.swift`: the rules, balance, unlocks, passes and cooldowns.
- `Flowstate/Views/Earned/EarnedTimeView.swift`: the Earned time sheet, plus `EarnedBadge`, `BalanceRing` and the rule cards.
- `FlowstateMonitor/`: the DeviceActivity monitor extension (Swift, Info.plist, entitlements, privacy manifest).
- `FlowstateTests/EarnedTimeRulesTests.swift` and `FlowstateTests/ScheduleTests.swift`.

**Edited files:**
- `Shared/ScreenTime.swift`:
  - removed the `.earned` store name, `EarnedShield`, the `DeviceActivityName` unlock names, `DeviceActivitySchedule.window` and `DeviceActivityCenter.startMonitoring(_:from:to:)`, and the distracting-apps load/save;
  - added `RetiredEarnedShield`.
- `Flowstate/Services/BlockingManager.swift`: calls `RetiredEarnedShield.clear()` on launch.
- `Flowstate/Services/SessionManager.swift`:
  - no `EarnedTimeManager`, and no crediting at session end;
  - `SessionSummary` lost `earnedMinutes`, `balanceFull` and `deepFocus`.
- `Flowstate/App/FlowstateApp.swift`, `Flowstate/Views/RootView.swift`: no `EarnedTimeManager` in the environment, and no 1-second `earned.refresh()` loop.
- `Flowstate/Views/Focus/FocusView.swift`: no earned badge under "focused today", no Earned time sheet, no `-debugSheet earned`.
- `Flowstate/Views/Focus/ActiveSessionView.swift`:
  - the running screen lost "+X of scrolling earned" and the "Deep focus · 1.5× bonus" label (with its haptic);
  - the summary lost the "Scrolling earned" and "Deep focus bonus" rows.
- `Flowstate/Views/Profile/ProfileView.swift`: no "Add 30 min earned time" debug button.
- `project.yml`: no `FlowstateMonitor` target or dependency.
- `scripts/testflight.sh`: no step that strips the monitor extension.
- `README.md`: removed "Earning scrolling time", "Spending it" and the cooldown bullet; the earned screenshot became the Subjects one.
- `Flowstate/Resources/PrivacyInfo.xcprivacy`: comment wording only.

## What stayed behind (on purpose)

- **The saved state:** balance, mode, today's unlocks and passes, pending changes. It sits in the app's `UserDefaults` under `earned.*` keys: `earned.balance`, `earned.mode`, `earned.unlockedToday`, `earned.passesUsedToday`, `earned.activeUnlock`, `earned.day`, `earned.pendingMode`, `earned.pendingDistracting`. Nothing reads it now, so a restored build picks up where it left off.
- **The distracting-app choice:** still in the App Group under `distractingSelection`.
- **`RetiredEarnedShield.clear()`:** runs on every launch. iOS keeps an app's shields across updates, so without it distracting apps would stay blocked with no way left to unlock them. It also stops any DeviceActivity monitoring.
- **The marketing screenshots** `04-earned.png` and `04b-how-you-earn.png` are still in `marketing/screenshots/`.

# #965 — Is the Scene's Commands tree a material cold-launch cost?

**Status: NOT YET MEASURED.** This file is a runbook, not a result. The results table below is empty because nobody has run the experiment yet, and until it is filled in, nothing here should be cited as evidence that the hypothesis holds. Filling in that table is the artifact WXYC/wxyc-ios-64#965's first acceptance criterion asks for.

## Hypothesis

The `.commands { WXYCCommandMenus(appState: appState) }` attachment on `WXYCApp`'s `WindowGroup` forces recursive Swift runtime type-metadata and protocol-conformance resolution on the main thread during scene instantiation, and that resolution is expensive enough to show up as user-visible cold-launch latency. The evidence is Sentry IOS-42 event `6b3cd47ea88e4005be917c5d7b60d1d3` (iPhone14,7, `device.class: high`, app version `3.2+6`), whose main-thread stack runs `runApp<T> → Update.dispatchImmediately<T> → GraphHost.instantiate → AppGraph.instantiateOutputs → ModifiedContent<T>._makeScene → CommandsModifier._makeScene → Commands._makeCommands → Commands.makeBody → BodyAccessor.makeBody → swift_getAssociatedTypeWitnessSlowImpl → swift_getTypeByMangledName` (roughly 20 recursive frames) `→ TypeDecoder<T>::decodeMangledType → DecodedMetadataBuilder::createBoundGenericType → swift::_checkGenericRequirements → swift::_conformsToProtocol → dyld4::APIs::_dyld_find_protocol_conformance → SwiftHashTable::getPotentialTarget<T>` — a conformance-lookup hash probe with `Commands._makeCommands` as the direct parent of the demangler recursion.

This branch (`experiment/commands-variant-b`) is variant B of the A/B comparison the ticket asks for: the `.commands` attachment is deleted from `WXYCApp.swift` while `WXYCCommandMenus.swift` is left in place untouched. It exists purely so the measurement below is one build away when a device is free. **This branch must never be merged.** It is not a fix, it drops the app's entire keyboard-shortcut surface, and it exists to falsify or confirm a hypothesis, not to ship.

The deletion is deliberately crude — total removal rather than one of the candidate fixes — because it establishes the *upper bound* on what the tree costs. If the upper bound is not worth having, none of the narrower fixes are either, and the hypothesis is refuted without needing to build them. Do not "improve" variant B into a candidate fix; choosing among the candidates is what the measurement is for.

## What variant B changes behaviourally

Detaching the tree removes every keyboard shortcut the app has. There are six key-bound shortcuts, all of them defined in `WXYCCommandMenus.swift` and nowhere else — the app has no view-level `.keyboardShortcut` modifiers to fall back on:

| Key | Action | Notes |
|---|---|---|
| Space | Play/Pause | `AudioPlayerController.shared.toggle(reason: .keyboardShortcut)` |
| Return | Toggle Theme Picker | |
| Left Arrow | Previous Theme | disabled unless the theme picker is active |
| Right Arrow | Next Theme | disabled unless the theme picker is active |
| `k` | Switch to Previous Theme | always available; switches outright with the picker closed |
| `j` | Switch to Next Theme | always available; switches outright with the picker closed |

The `DEBUG`/`DEBUG_TESTFLIGHT`-only Debug menu also contributes a shortcut-less "Trigger Background Refresh" item, which variant B removes as well.

Per platform: on iPhone the loss is invisible without a hardware keyboard attached and total with one; on iPad with a hardware keyboard all six shortcuts are gone; on Mac Catalyst the `Commands` tree additionally populates the menu bar, so variant B loses the "Playback", "Themes", and (in non-release builds) "Debug" menus there in addition to the shortcuts.

This table doubles as the variant sanity check in step 7 below.

## What to measure

Compare cold launch-to-first-frame between two variants of the same base commit. "Launch-to-first-frame" is the term used throughout this document and is the App Launch template's own phase name; it is the interval from process start to the first frame the user sees.

- **Variant A** — the commit this branch is based on: `26f79dbae`. Use that commit, not whatever `master` has become by the time you measure; `master` moves, and an unrelated change landing between the two builds confounds the comparison. `git merge-base origin/master experiment/commands-variant-b` recovers it.
- **Variant B** — this branch, `experiment/commands-variant-b`, whose only code change against that base is the deleted attachment.

Build **Release**, not Debug. A Debug build is unoptimized, links differently, and carries testability and assertion overhead that swamps the effect being measured; a cold-launch number taken from a Debug build says nothing about the shipping app. Xcode's Profile action uses the Release configuration by default — keep it that way.

Watch out for a second trap here, and note that the obvious defence against it does not work. Only the `Debug` configuration installs under a distinct bundle identifier (`org.wxyc.iphoneappdebug`); `Debug TestFlight`, `TestFlight`, `Release`, and `Release (Active Arch)` **all** install as `org.wxyc.iphoneapp`, and every one of them displays as "WXYC" on the Home Screen. So targeting the bundle identifier tells you only that you are not on the `Debug` build — it cannot tell a Release install from a `Debug TestFlight` one. The rules that actually hold: delete every WXYC build from the device before starting, install exactly one variant at a time, and **do not run the test suite against the device mid-session** — `xcodebuild test -scheme WXYC` builds `Debug TestFlight`, which silently overwrites your Release install at the same bundle identifier and leaves you profiling an unoptimized binary that looks correct from the outside.

### Capturing an Instruments App Launch trace on a physical device

1. Pick a qualifying device first — read "Affected device population" below before doing anything else, because the wrong device (any simulator, and to a lesser extent a current-generation Pro) invalidates the whole session. Then delete every existing WXYC build from that device (see the bundle-identifier trap above) and install variant A to it in the **Release** configuration. Use **Product → Profile (Cmd-I)**, whose `ProfileAction` is `Release`. Do *not* use Cmd-R: the scheme's `LaunchAction` is `Debug`, so the obvious keystroke installs `org.wxyc.iphoneappdebug` — the exact trap described just above. If you would rather use the Run action, change its configuration to `Release` in the scheme editor first.
2. Launch the app once and discard that run. The first launch after an install does first-run-only work — data-protection class setup, cache directory creation, the app's own first-launch paths — that is not representative of a steady-state cold launch.
3. Open Instruments (Xcode → Open Developer Tool → Instruments, or Product → Profile, which builds Release) and choose the **App Launch** template, targeting the device and the WXYC app.
4. Force a genuinely cold launch before **each** measured run, by rebooting the device. Be precise about why, because the naive version of this claim is wrong: Swift's type-metadata, demangled-type, and conformance caches are *process-local* runtime hash tables, so they die with the process and are cold on every relaunch, warm or not. What a reboot actually clears is the OS-side state that determines how *expensive* those cold lookups are — the resident pages of the dyld shared cache that `_dyld_find_protocol_conformance` probes, the app's prebuilt launch closure, and the unified buffer cache holding the app binary. A force-quit relaunch therefore still performs the metadata work, but performs it against memory-resident pages, which compresses the A-versus-B difference toward zero and understates the cost the Sentry hangs were sampled from. The measurement has to reproduce the state real users launch into, and that is a cold boot. Specifically:
   - Reboot the device, unlock it, and then wait about two minutes before launching. The reboot is what evicts the page-resident state; the wait is because the first minute after unlock is full of boot-time daemon activity, Spotlight indexing, and iCloud sync that adds noise unrelated to either variant.
   - Do not substitute force-quitting the app from the app switcher, or Instruments' own "terminate before launch" behaviour. Both give you a fresh process against a warm page cache, which is the measurement that understates the effect.
   - Do not launch with the Xcode debugger attached (Cmd-R). The debugger materially inflates launch time and changes dyld behaviour. Instruments launches the app itself; let it.
   - Keep the device plugged in, off Low Power Mode, out of thermal throttling (let it cool between runs if it is warm to the touch), and on the same iOS version and network conditions for both variants.
5. Record the App Launch template's launch-to-first-frame interval. The template breaks the launch into phases (system interface init, static runtime init, UIKit/scene init, first frame render); the total through first frame render is the headline number, and the per-phase split is worth keeping because the hypothesis predicts the improvement lands specifically in the scene-initialization phase rather than spreading evenly. **Save every capture** as `<device>-<variant>-run<N>.trace` before starting the next run. Each data point costs a full reboot-and-settle cycle, so an unsaved trace that turns out to be ambiguous later — an outlier worth re-checking, a phase split you did not read carefully, a borderline call on step 6 — can only be recovered by collecting it again from scratch.
6. Also record, per variant, whether the `Commands._makeCommands` → `swift_getTypeByMangledName` frames appear anywhere in the trace's main-thread samples. This is a qualitative check but a strong one: those frames should be present in variant A and absent in variant B by construction, and if they never appear in A's trace at all, the trace is not sampling the window the Sentry stack came from and the timing numbers from it are not answering the question.
7. Sanity-check that you actually installed the variant you think you did. Measuring the same build twice is the most common way an A/B like this produces a confident null result. The check that always works, and needs no extra hardware, is step 6's frame inspection: variant A's trace contains `Commands._makeCommands` and variant B's cannot, by construction. Confirm that on the first run of each block, before spending reboot cycles on the rest. If a hardware keyboard happens to be attached, Space toggling playback on A and doing nothing on B is a faster confirmation of the same fact; on Mac Catalyst, variant A has "Playback" and "Themes" in the menu bar and variant B does not. Neither of those is available on a bare handset, which is the expected measurement device, so treat the trace check as the primary one.
8. Repeat steps 4-7 for the run count below. Then switch variants: delete the variant A install, install **variant B** from this branch by repeating step 1 (substituting this branch for `26f79dbae`) and step 2, and run steps 3-7 again for it. Note that step 1 as written installs variant A — read it with the substitution, or you will reinstall and re-measure A and produce exactly the false null step 7 exists to catch.
9. Finally, reinstall **variant A** and take two or three more runs of it as a drift check. This is a real step, not optional bookkeeping: it is the only evidence that the device stayed in a comparable state across the session. Repeat step 2's discard — a reinstall means the next launch is a first-launch-after-install, and with only two or three runs in this block that inflated launch would dominate the repeat median and manufacture drift that is not there.

As a scriptable alternative to driving Instruments by hand, `xcrun xctrace record --device <device-udid> --template 'App Launch' --launch <bundle-id> --output <name>.trace` captures the same trace from the terminal, which makes the per-run bookkeeping easier. Check `xcrun xctrace record --help` for your Xcode version before relying on the exact flag spelling. The reboot-before-each-run requirement is unchanged and cannot be scripted away.

### Affected device population

The IOS-42 stacks that motivated this hypothesis come from iPhone14,x and iPhone11,8. `iPhone14,7` — the identifier on the specific event cited above — is the iPhone 14; the `iPhone14,x` family also spans the iPhone 13 line, the iPhone 14 Plus, and the third-generation iPhone SE. `iPhone11,8` is the iPhone XR. Both are mid-tier, non-Pro devices several generations behind current hardware. Measure on a device from this population, or on a comparable mid-tier device still in the field.

**A simulator is not a valid measurement target, and an M-series simulator especially so.** The simulator runs the app as a native Mac process against the host's dyld shared cache, on Mac silicon with a different memory hierarchy, and there is no way to cold-start it in the sense that matters here. It will not reproduce the on-device conformance-lookup cost the stack shows, and a null result from a simulator is not evidence of anything. If the only hardware available is a current-generation Pro device, that is a weaker but still admissible target — record the model in the results table so the reader can discount it accordingly.

### Run count and statistic

Take at least 5 cold launches per variant per device, and more if the spread across runs is wide. Report the **median** launch-to-first-frame time, not a single run and not the mean — cold launches have a long right tail (thermal throttling, background daemon contention, a straggler disk read), and the median is robust to that tail in a way a single number or a mean is not. Record the minimum and maximum alongside it, and keep the individual runs.

**Check variant A's own spread before you start on variant B.** A full session is roughly 12 to 13 reboot-and-settle cycles, an hour or more of device time, and it is worth knowing early whether this device can resolve anything at all. If A's five runs are scattered across hundreds of milliseconds, the session cannot detect an effect of the size this hypothesis predicts no matter how careful the rest of it is — stop, fix the device state (thermals, Low Power Mode, a background restore or iCloud sync still running, another app misbehaving), and restart the A block rather than spending another 40 minutes collecting a B block that cannot be compared to it.

The session is bracketed: measure A, then B, then step 9's short repeat of A. The repeat is what converts "the medians differ" into "the medians differ by more than this device drifts," and the decision rule below leans on it directly. If the repeat median lands far from the first A median, the device did not hold still and the session should be discarded rather than reported.

### Results table

Fill in one row per (device, variant) pair actually measured. Add rows as needed for additional devices. Keep the individual run values, not just the summary — a future reader cannot re-derive the spread from a median alone.

| Device model | iOS version | Variant | Run count | Median launch-to-first-frame | Min / max | Individual runs | `Commands._makeCommands` in trace? |
|---|---|---|---|---|---|---|---|
| | | A (`26f79dbae`) | | | | | |
| | | B (commands detached) | | | | | |
| | | A (repeat, drift check) | | | | | |

**Verdict:** _(confirmed / refuted — apply the decision rule in the next section before filling this in, then record the number behind it here and mirror the verdict into #965)_

## Decision rule

Adapted from the ticket's "What would refute this" section. #965 says "no *measurable* improvement" without defining measurable; the first bullet below is this document's attempt to make that executable, and it is the one part of the rule that is not the ticket's own text.

- **Before applying any of this, confirm the trace was valid.** If `Commands._makeCommands` never appeared in variant A's traces (the last column of the results table), the trace did not sample the window the Sentry stack came from, and a flat A-versus-B delta says nothing about the hypothesis. That is an inconclusive session to be re-run, not a refutation. Refuting #965 on a trace that never observed the code under test would close the ticket on a false negative and misdirect #949.
- If the A-versus-B median difference is not clearly larger than the A-versus-A-repeat median difference from step 9, the hypothesis is **refuted**: the `Commands` frame in the IOS-42 stack is incidental — it happens to be where the sample landed inside a broader metadata-instantiation cost driven by the root view — and the work belongs on `RootTabView`'s modifier chain instead. Use the repeat block as the comparison, not the raw min-to-max spread of individual runs: on a mid-tier handset that spread routinely covers hundreds of milliseconds, and testing against it would score a real 40-to-80ms scene-init win as a null. The per-phase split from step 5 is corroborating evidence either way — a genuine effect should concentrate in the scene-initialization phase, and a delta smeared evenly across all phases is a sign you are looking at device noise rather than at the Commands tree.
- If the `swift_getTypeByMangledName` recursion still appears in IOS-42 stacks on a shipped build carrying one of the candidate fixes, that is also a refutation. (The ticket phrases this as "a build shipping variant B"; no such build will ever exist, since this branch is never merged, so the check necessarily lands on whichever fix ships.)
- **Refutation is a valid, useful outcome, not a failed experiment.** Record it and close the hypothesis in #965 — do not leave the issue open as a presumed fix, and do not treat "inconclusive" as license to keep it open indefinitely. If refuted, #965 closes and WXYC/wxyc-ios-64#949 item 1 narrows to the root-view modifier chain alone, per #949's own acceptance criteria.
- If confirmed, #965's acceptance criteria call for implementing one of the three options it enumerates (`#if targetEnvironment(macCatalyst)`, view-level `.keyboardShortcut` migration, or shrinking the `CommandMenu` type) on a separate branch — not this one — with the keyboard-shortcut coverage change stated per platform and `WXYCCommandMenus.swift` still existing. Which of the three is appropriate depends on the size of the measured win and on whether iPad hardware-keyboard use matters; that is a decision to make with the number in hand, not before.
- Whichever way it goes, the ticket also forbids raising `appHangTimeoutInterval` to make the numbers look better. That is not a measurement, it is a way of not taking one.

## A caution on verifying via Sentry after the fact

If a fix ships, do not use IOS-42's raw event count to declare victory. Sentry groups every launch hang under the single `WXYCApp.$main` frame — the only in-app frame present at launch — so the event count does not distinguish "still the Commands cost" from "some other launch cost now dominates" from "actually fixed." Verify instead by checking whether the `Commands._makeCommands` → `swift_getTypeByMangledName` stack *shape* has disappeared from IOS-42 samples on builds carrying the fix, not by whether the count went down. This gets easier once WXYC/wxyc-ios-64#952 lands and separates the group by stack shape; until then, pull individual event stacks and compare by hand.

## Why there is no in-app instrumentation to fall back on

An Instruments trace is the only ground truth available today because Sentry's launch profiling is deliberately off: `options.enableAppLaunchProfiling = false` in `WXYCApp.swift`, disabled because it accumulates 10-20MB of stack samples, with a comment pointing at Instruments as the intended substitute. #965 lists `os_signpost` intervals bracketing scene instantiation as a second-choice option, and #949's acceptance criteria want those checked in anyway; if this measurement gets run often enough to be annoying, adding the signposts is the way to make it cheap. Do not enable Sentry launch profiling just to take this one measurement.

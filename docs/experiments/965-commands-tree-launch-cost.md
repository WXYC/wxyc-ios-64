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

Compare cold-launch-to-first-render between two variants of the same base commit:

- **Variant A** — the commit this branch is based on: `26f79dbae`. Use that commit, not whatever `master` has become by the time you measure; `master` moves, and an unrelated change landing between the two builds confounds the comparison. `git merge-base origin/master experiment/commands-variant-b` recovers it.
- **Variant B** — this branch, `experiment/commands-variant-b`, whose only code change against that base is the deleted attachment.

Build **Release**, not Debug. A Debug build is unoptimized, links differently, and carries testability and assertion overhead that swamps the effect being measured; a cold-launch number taken from a Debug build says nothing about the shipping app. Xcode's Profile action uses the Release configuration by default — keep it that way.

Watch out for a second trap here: the Debug configuration installs under bundle identifier `org.wxyc.iphoneappdebug` while Release/TestFlight install under `org.wxyc.iphoneapp`, and both display the same name on the Home Screen. It is entirely possible to have two WXYC icons installed and profile the wrong one for an hour. Delete other WXYC builds from the device before starting, or always target the bundle identifier explicitly rather than tapping an icon.

### Capturing an Instruments App Launch trace on a physical device

1. Delete any existing WXYC builds from the device (see the bundle-identifier trap above), then build variant A in the **Release** configuration to the device.
2. Launch the app once and discard that run. The first launch after an install does first-run-only work — data-protection class setup, cache directory creation, the app's own first-launch paths — that is not representative of a steady-state cold launch.
3. Open Instruments (Xcode → Open Developer Tool → Instruments, or Product → Profile, which builds Release) and choose the **App Launch** template, targeting the device and the WXYC app.
4. Force a genuinely cold launch before **each** measured run, by rebooting the device. Metadata instantiation is heavily cache-dependent: the dyld shared-cache protocol-conformance tables and Swift's demangled-type cache both stay warm across app relaunches, so a warm launch measures the cache rather than the cost this hypothesis is about, and will show no difference between the variants regardless of whether the hypothesis is true. Specifically:
   - Reboot the device, unlock it, and then wait about two minutes before launching. The reboot is what clears the caches; the wait is because the first minute after unlock is full of boot-time daemon activity, Spotlight indexing, and iCloud sync that adds noise unrelated to either variant.
   - Do not substitute force-quitting the app from the app switcher, or Instruments' own "terminate before launch" behaviour. Both give you a fresh process against warm caches, which is exactly the measurement that cannot distinguish the variants.
   - Do not launch with the Xcode debugger attached (Cmd-R). The debugger materially inflates launch time and changes dyld behaviour. Instruments launches the app itself; let it.
   - Keep the device plugged in, off Low Power Mode, out of thermal throttling (let it cool between runs if it is warm to the touch), and on the same iOS version and network conditions for both variants.
5. Record the App Launch template's launch-to-first-frame interval. The template breaks the launch into phases (system interface init, static runtime init, UIKit/scene init, first frame render); the total through first frame render is the headline number, and the per-phase split is worth keeping because the hypothesis predicts the improvement lands specifically in the scene-initialization phase rather than spreading evenly.
6. Also record, per variant, whether the `Commands._makeCommands` → `swift_getTypeByMangledName` frames appear anywhere in the trace's main-thread samples. This is a qualitative check but a strong one: those frames should be present in variant A and absent in variant B by construction, and if they never appear in A's trace at all, the trace is not sampling the window the Sentry stack came from and the timing numbers from it are not answering the question.
7. Sanity-check that you actually installed the variant you think you did, using the behaviour table above: with a hardware keyboard attached, Space toggles playback on variant A and does nothing on variant B. On Mac Catalyst, variant A has "Playback" and "Themes" menus in the menu bar and variant B does not. Measuring the same build twice is the most common way an A/B like this produces a confident null result.
8. Repeat steps 4-7 for the run count below, then build variant B and repeat from step 1.

As a scriptable alternative to driving Instruments by hand, `xcrun xctrace record --device <device-udid> --template 'App Launch' --launch <bundle-id> --output <name>.trace` captures the same trace from the terminal, which makes the per-run bookkeeping easier. Check `xcrun xctrace record --help` for your Xcode version before relying on the exact flag spelling. The reboot-before-each-run requirement is unchanged and cannot be scripted away.

### Affected device population

The IOS-42 stacks that motivated this hypothesis come from iPhone14,x and iPhone11,8. `iPhone14,7` — the identifier on the specific event cited above — is the iPhone 14; the `iPhone14,x` family also spans the iPhone 13 line, the iPhone 14 Plus, and the third-generation iPhone SE. `iPhone11,8` is the iPhone XR. Both are mid-tier, non-Pro devices several generations behind current hardware. Measure on a device from this population, or on a comparable mid-tier device still in the field.

**A simulator is not a valid measurement target, and an M-series simulator especially so.** The simulator runs the app as a native Mac process against the host's dyld shared cache, on Mac silicon with a different memory hierarchy, and there is no way to cold-start it in the sense that matters here. It will not reproduce the on-device conformance-lookup cost the stack shows, and a null result from a simulator is not evidence of anything. If the only hardware available is a current-generation Pro device, that is a weaker but still admissible target — record the model in the results table so the reader can discount it accordingly.

### Run count and statistic

Take at least 5 cold launches per variant per device, and more if the spread across runs is wide. Report the **median** launch-to-first-frame time, not a single run and not the mean — cold launches have a long right tail (thermal throttling, background daemon contention, a straggler disk read), and the median is robust to that tail in a way a single number or a mean is not. Record the minimum and maximum alongside it: the spread is what tells you whether any difference between the medians is real.

Measure A, then B, then re-measure two or three runs of A. If the second A median has drifted away from the first by anything comparable to the A-versus-B difference, the device was not in a stable state and the whole session should be discarded rather than reported.

### Results table

Fill in one row per (device, variant) pair actually measured. Add rows as needed for additional devices. Keep the individual run values, not just the summary — a future reader cannot re-derive the spread from a median alone.

| Device model | iOS version | Variant | Run count | Median launch-to-first-frame | Min / max | Individual runs | `Commands._makeCommands` in trace? |
|---|---|---|---|---|---|---|---|
| | | A (`26f79dbae`) | | | | | |
| | | B (commands detached) | | | | | |
| | | A (repeat, drift check) | | | | | |

**Verdict:** _(confirmed / refuted — fill in, with the number behind it, and mirror it into #965)_

## Decision rule

From the ticket's "What would refute this" section. Apply it as written; do not soften it.

- If variant B shows no improvement over A larger than the run-to-run spread within either variant, the hypothesis is **refuted**: the `Commands` frame in the IOS-42 stack is incidental — it happens to be where the sample landed inside a broader metadata-instantiation cost driven by the root view — and the work belongs on `RootTabView`'s modifier chain instead. Two medians differing by less than the noise floor is a null result, not a small positive one.
- If the `swift_getTypeByMangledName` recursion still appears in IOS-42 stacks on a build shipping variant B, that is also a refutation.
- **Refutation is a valid, useful outcome, not a failed experiment.** Record it and close the hypothesis in #965 — do not leave the issue open as a presumed fix, and do not treat "inconclusive" as license to keep it open indefinitely. If refuted, #965 closes and WXYC/wxyc-ios-64#949 item 1 narrows to the root-view modifier chain alone, per #949's own acceptance criteria.
- If confirmed, #965's acceptance criteria call for implementing one of the three options it enumerates (`#if targetEnvironment(macCatalyst)`, view-level `.keyboardShortcut` migration, or shrinking the `CommandMenu` type) on a separate branch — not this one — with the keyboard-shortcut coverage change stated per platform and `WXYCCommandMenus.swift` still existing. Which of the three is appropriate depends on the size of the measured win and on whether iPad hardware-keyboard use matters; that is a decision to make with the number in hand, not before.
- Whichever way it goes, the ticket also forbids raising `appHangTimeoutInterval` to make the numbers look better. That is not a measurement, it is a way of not taking one.

## A caution on verifying via Sentry after the fact

If a fix ships, do not use IOS-42's raw event count to declare victory. Sentry groups every launch hang under the single `WXYCApp.$main` frame — the only in-app frame present at launch — so the event count does not distinguish "still the Commands cost" from "some other launch cost now dominates" from "actually fixed." Verify instead by checking whether the `Commands._makeCommands` → `swift_getTypeByMangledName` stack *shape* has disappeared from IOS-42 samples on builds carrying the fix, not by whether the count went down. This gets easier once WXYC/wxyc-ios-64#952 lands and separates the group by stack shape; until then, pull individual event stacks and compare by hand.

## Why there is no in-app instrumentation to fall back on

An Instruments trace is the only ground truth available today because Sentry's launch profiling is deliberately off: `options.enableAppLaunchProfiling = false` in `WXYCApp.swift`, disabled because it accumulates 10-20MB of stack samples, with a comment pointing at Instruments as the intended substitute. #965 lists `os_signpost` intervals bracketing scene instantiation as a second-choice option, and #949's acceptance criteria want those checked in anyway; if this measurement gets run often enough to be annoying, adding the signposts is the way to make it cheap. Do not enable Sentry launch profiling just to take this one measurement.

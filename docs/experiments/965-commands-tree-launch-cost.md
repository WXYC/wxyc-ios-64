# #965 — Is the Scene's Commands tree a material cold-launch cost?

## Hypothesis

The `.commands { WXYCCommandMenus(appState: appState) }` attachment on `WXYCApp`'s `WindowGroup` forces recursive Swift runtime type-metadata and protocol-conformance resolution on the main thread during scene instantiation, and that resolution is expensive enough to show up as user-visible cold-launch latency. The evidence is Sentry IOS-42 event `6b3cd47ea88e4005be917c5d7b60d1d3` (iPhone14,7, `device.class: high`, app version `3.2+6`), whose main-thread stack runs `runApp<T> → Update.dispatchImmediately<T> → GraphHost.instantiate → AppGraph.instantiateOutputs → ModifiedContent<T>._makeScene → CommandsModifier._makeScene → Commands._makeCommands → Commands.makeBody → BodyAccessor.makeBody → swift_getAssociatedTypeWitnessSlowImpl → swift_getTypeByMangledName` (roughly 20 recursive frames) `→ TypeDecoder<T>::decodeMangledType → DecodedMetadataBuilder::createBoundGenericType → swift::_checkGenericRequirements → swift::_conformsToProtocol → dyld4::APIs::_dyld_find_protocol_conformance → SwiftHashTable::getPotentialTarget<T>` — a conformance-lookup hash probe with `Commands._makeCommands` as the direct parent of the demangler recursion.

This branch (`experiment/commands-variant-b`) is variant B of the A/B comparison the ticket asks for: the `.commands` attachment is deleted from `WXYCApp.swift` while `WXYCCommandMenus.swift` is left in place untouched. It exists purely so the measurement below is one build away when a device is free. **This branch must never be merged.** It is not a fix, it silently drops the app's entire keyboard-shortcut surface, and it exists to falsify or confirm a hypothesis, not to ship.

## What to measure

Compare cold-launch-to-first-render between two variants of the same commit:

- **Variant A** — unmodified `origin/master`.
- **Variant B** — this branch, `experiment/commands-variant-b`.

### Capturing an Instruments App Launch trace on a physical device

1. Connect a device from the affected population (see below) and select it as the run destination in Xcode.
2. Open Instruments (Xcode → Open Developer Tool → Instruments, or `xcrun xctrace`) and choose the **App Launch** template. This is the only ground-truth measurement available today — `enableAppLaunchProfiling` is deliberately `false` in `WXYCApp.swift` (Sentry launch profiling is disabled to avoid its 10-20MB stack-sample memory overhead; see the comment near line 297), so there is no in-app instrumentation to fall back on for this measurement.
3. Force a genuinely cold launch before each run. Metadata instantiation is heavily cache-dependent — the dyld protocol-conformance cache and Swift's demangled-type cache both persist across warm launches, so a warm launch measures the cache, not the cost this hypothesis is about. Use one of:
   - Reboot the device immediately before each launch, or
   - Let the device sit idle (screen off, backgrounded) for long enough that iOS has evicted the app's process and its caches — in practice this means idling well past the time it takes iOS to jetsam a backgrounded app, not just a few minutes.
   A `Cmd-R` re-run from Xcode with the device still awake and the app still resident is not cold. If Instruments offers a "Launch" configuration with a "Terminate app before each run" or similar option, that still is not equivalent to a device-level cold start for this measurement, because it does not clear the dyld/demangler caches — do the reboot-or-idle step regardless.
4. Record the App Launch trace's launch-to-first-render interval (the template reports this directly; if it does not break out a single number, use time from process start to the first `CA::Transaction::commit` / first frame).
5. Repeat for several cold launches on the same device and app variant before switching variants, per the run-count guidance below.
6. Install variant B by building this branch (`experiment/commands-variant-b`) to the device and repeat steps 2-5.

### Affected device population

The IOS-42 stacks that motivated this hypothesis come from iPhone14,x (iPhone 13 family) and iPhone11,8 (iPhone XR) — both mid-tier, non-Pro devices, `device.class: high` at the time they shipped but several generations behind current hardware. Measure on a device from this population or a comparable mid-tier device still in the field. An M-series simulator (or any simulator) is not a valid measurement target: the simulator runs on Mac silicon with a completely different memory/dyld-cache profile, and simulator "cold launch" does not reproduce the on-device conformance-lookup cost the stack shows.

### Run count and statistic

Take at least 5 cold launches per variant per device (more if the spread across runs is wide). Report the **median** launch-to-first-render time, not a single run and not the mean — cold launches have a long right tail (thermal throttling, background daemon contention, a straggler disk read), and the median is robust to that tail in a way a single number or a mean is not.

### Results table

Fill in one row per (device, variant) pair actually measured. Add rows as needed for additional devices.

| Device model | iOS version | Variant | Run count | Median launch-to-first-render |
|---|---|---|---|---|
| | | A (master) | | |
| | | B (commands detached) | | |

## Decision rule

Copied from the ticket's "What would refute this" section — apply it exactly, do not soften it:

- If variant B shows no measurable improvement over A, the `Commands` frame in the IOS-42 stack is incidental — it happens to be where the sample landed inside a broader metadata-instantiation cost driven by the root view, and the work belongs on `RootTabView`'s modifier chain instead.
- If the `swift_getTypeByMangledName` recursion still appears in IOS-42 stacks on a build shipping variant B, that is also a refutation.
- **Either outcome is a useful result.** Record it and close the hypothesis in #965 — do not leave the issue open as a presumed fix, and do not treat "inconclusive" as license to keep it open indefinitely. If refuted, #965 closes and WXYC/wxyc-ios-64#949 item 1 narrows to the root-view modifier chain alone, per #949's own acceptance criteria.
- If confirmed, #965's acceptance criteria call for implementing one of the three options it enumerates (`#if targetEnvironment(macCatalyst)`, view-level `.keyboardShortcut` migration, or shrinking the `CommandMenu` type) on a separate branch — not this one — with the keyboard-shortcut coverage change stated per platform and `WXYCCommandMenus.swift` still existing.

## A caution on verifying via Sentry after the fact

If a fix ships, do not use IOS-42's raw event count to declare victory. Sentry groups every launch hang under the single `WXYCApp.$main` frame — the only in-app frame present at launch — so the event count does not distinguish "still the Commands cost" from "some other launch cost now dominates" from "actually fixed." Verify instead by checking whether the `Commands._makeCommands` → `swift_getTypeByMangledName` stack *shape* has disappeared from IOS-42 samples on builds carrying the fix, not by whether the count went down. This gets easier once WXYC/wxyc-ios-64#952 lands and separates the group by stack shape; until then, pull individual event stacks and compare by hand.

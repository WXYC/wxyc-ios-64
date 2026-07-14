# On Tour — poster detail (B2, full-ticket tuck)

## Goal

Replace the "barren" On Tour event-detail `.sheet` (a `BoxOfficeTicketView` on a flat gradient) with a **poster-first detail** that zooms up from the tapped row. This is the implementation of the decided prototype `docs/ideas/on-tour-poster-layouts.html`, layout **B2 (Tucked Ticket)**, resolved down to the shipped Box Office ticket as the tucked card.

Not part of the R2/R3 filter chain in `474-touring-soon-tab.md`; this is a follow-on refinement of R1's detail surface.

**Branch:** `on-tour-poster-detail` (worktree at `.claude/worktrees/on-tour-poster-detail`). Rebase on `origin/master` before opening the PR (this repo's default branch is `master`, not `main`).

## Locked decisions

- **Arrival:** tap a row → it **zooms into a full-bleed poster** (`.matchedTransitionSource` on the row → `.navigationTransition(.zoom)` on the destination), presented as a `.fullScreenCover`. Replaces `.sheet(item: $selectedConcert)`.
- **Tucked card = the full shipped `BoxOfficeTicketView`** (user decision), tucked under the poster's bottom edge. Preserves the keepsake's equity rather than a lighter purpose-made card.
- **Poster art:** always show the poster treatment. When `image_url` is present, use it (`AsyncImage`); when null (the common case today), render a **deterministic per-show gradient** keyed off the venue slug / headliner. No gating on image coverage.
- **Provenance block deferred:** the "You heard X on WXYC · last spun …" block has no play-history data source wired. Omit from v1; file a follow-up ticket to add it once play-history is available.

## Page structure (top → bottom)

1. **Poster hero** — full-bleed art (photo or gradient) extending under the Dynamic Island, big faint artist initial, bottom scrim. Over it, bottom-aligned: status pill (if any) + **artist name** (large) + a compact credit line (`SAT AUG 1 · Carrboro`). Back button top-left.
2. **Tucked Box Office ticket** — the existing `BoxOfficeTicketView(show:)`, pulled up (`~ -28pt`) to straddle the poster seam, on the dark body panel. Carries venue / doors·show·price / support+age / status pill / **CTA + caption** (the outbound action, thumb-height). No separate dock.
3. **Where** — venue name + address (when present) + a **Directions** button opening Apple Maps for the venue. (Decorative map only if cheap; address is often null.)
4. **More touring soon** *(PR2, not PR1)* — a horizontal rail of up-to-N *other* concerts (same venue first, then rest), tapping one re-navigates to that concert's detail.

**PR1 is complete and shippable without the rail** — poster hero + tucked ticket + Where fully replace the sheet. The rail (sibling-list plumbing + re-navigation to a different concert + horizontal scroll) is its own vertical slice with its own tests, so it is **PR2 unconditionally**, not a "fits if it's small" call.

The ticket already renders the "bill" (support in its subline) and the stats grid, so no separate Details/Bill blocks — that avoids duplicating the ticket.

## Architecture / files

- **New:** `WXYC/iOS/Views/Touring/ConcertDetailView.swift` — the poster destination. App target (can use `BoxOfficeTicketView` directly, which is app-target `internal`). Takes the `Concert` plus the sibling list (or a small closure) for "More touring soon" and a re-select callback.
- **New:** `WXYC/iOS/Views/Touring/PosterArtView.swift` (or a nested helper) — `AsyncImage` with the gradient fallback; the gradient seed helper is pure and lives in `Shared/Concerts` for testability (see below).
- **Edit:** `TouringTabView.swift` — add `@Namespace zoom`; swap `.sheet(item:)` → `.fullScreenCover(item:)` presenting `ConcertDetailView` with `.navigationTransition(.zoom(sourceID: concert.id, in: zoom))`; pass the loaded list for the rail. Delete the private `ConcertDetailSheet`.
- **Edit:** `ConcertRow.swift` — accept the namespace; apply `.matchedTransitionSource(id: concert.id, in: zoom)` to the row.
- **Edit (Concerts pkg):** `BoxOfficeTicketPresenter.swift` — add pure, tested helpers the view needs:
  - `heroCreditLine` → `"SAT AUG 1 · Carrboro"` (compact date + city).
  - `subline` → move the `with … · age` logic out of `BoxOfficeTicketView` into the presenter (currently inline; make it testable and reuse it). **Sequence:** add `presenter.subline` + parity test first, prove it matches the current inline output, *then* rewire `BoxOfficeTicketView` to call it — so the refactor can't silently change the rendered string.
  - `directionsQuery` / `directionsURL` → an Apple Maps URL (`https://maps.apple.com/?q=…`) built from `name, address ?? "\(city), \(state)"`, percent-encoded. Never emits an empty address.
  - `PosterGradient.colors(for:)` (free function / small type in `Shared/Concerts`) → deterministic two-color pair. **Exact formula (canonical 64-bit FNV-1a, pinned in-code so a maintainer can't weaken it):**
    ```
    var hash: UInt64 = 0xcbf29ce484222325          // FNV offset basis
    for byte in "\(venue.slug)-\(id)".utf8 {
        hash ^= UInt64(byte)                        // XOR first (FNV-1a)
        hash = hash &* 0x100000001b3                 // then multiply by FNV prime (wrapping)
    }
    let index = Int(hash % UInt64(palette.count))
    ```
    Explicit `^` / `&*` — *not* Swift `hashValue` (per-run seeded). `palette` is a fixed ordered array of warm gradient pairs. Same concert → same pair on every run and every device.

Availability: `.matchedTransitionSource(id:in:)` and `.navigationTransition(.zoom(sourceID:in:))` are iOS 18.0 APIs (WWDC24). The app's deployment floor is 18.6 and the primary target is 26.0, so both are always available — **unconditional, no `#available` fence**. (They are *not* iOS-26-only; no `.sheet` fallback branch is needed.)

## TDD test list (Concerts pkg, `BoxOfficeTicketPresenterTests` + a new `PosterGradientTests`)

1. `heroCreditLine` = compact date + city only (e.g. `"SAT AUG 1 · Carrboro"`); **state and address are deliberately excluded** (the ticket carries the full where). Cases: date+city present → joined; city present, date always present (parsed from required `starts_on`, so no date-absent case); never renders an empty ` · ` slot.
2. `subline`: support+age → `"with A, B · 18+"`; support only; age only; neither → `nil` (parameterized). **Parity lock:** one case asserts `presenter.subline` equals the exact string the current inline `BoxOfficeTicketView.subline` builds (support before age, ` · ` separator) for each of the four shapes, added *before* the view is rewired.
3. `directionsURL`: built via `URLComponents` + `URLQueryItem` (encoding done by the components API, not by hand). Three cases: (a) full `address` present → `q = "name, address"`; (b) `address` null → `q = "name, city, state"`; (c) name only (empty city/state guarded) → `q = "name"`. Never emits an empty `q`.
4. `PosterGradient.colors(for:)`: **deterministic** (same concert → same pair, asserted by calling twice) and **run-stable** (assert a fixed concert maps to a known palette index — the explicit FNV-1a fold means the expected index can be hard-coded, which would fail if someone swapped in `hashValue`). Two visibly different seeds map to different pairs (best-effort, not a hard collision guarantee).

View layer (`ConcertDetailView`, `ConcertRow`, `TouringTabView`) is SwiftUI layout — covered by previews + the existing UI smoke test, not unit tests, per repo norms.

## PR slicing (aim ≤ ~1000 lines each)

- **PR1 (this plan):** presenter helpers + tests, `PosterGradient` + tests, `ConcertDetailView` (poster hero + tucked ticket + Where), and the zoom rewiring in `TouringTabView`/`ConcertRow`. Replaces the sheet end-to-end. **No rail.**
- **PR2 (unconditional):** "More touring soon" rail + re-navigation to a sibling concert's detail.
- **Follow-up ticket:** provenance block, wired when play-history data exists.

## Risks / watch-items

- **Ticket-on-dark-panel:** `BoxOfficeTicketView`'s background is `ZStack { MaterialView(); glassSurface }` — `MaterialView()` *draws the Metal wallpaper itself* (not a blur-of-behind). On the poster detail the body panel is a **dark scrim** (`Color.black.opacity(~0.55)` over the app's dark backdrop), so the ticket will contain a small window of live wallpaper floating over the poster. That may read as consistent app glass or may clash with the poster. **Decision gate (preview first):** if it clashes, add an opt-in `surface: .wallpaper | .darkGlass` parameter to `BoxOfficeTicketView` (default `.wallpaper`, keeping the playcut surface unchanged) and pass `.darkGlass` here. Do not change the playcut surface. Resolve in preview before wiring the transition.
- **Zoom + fullScreenCover:** `.navigationTransition(.zoom(sourceID:in:))` is supported on `.sheet`/`.fullScreenCover` presentations, not just NavigationStack pushes. Verified empirically by the build + a run on the iOS 26 sim and the 18.6 floor. Graceful degradation: if the zoom doesn't animate in some context, the cover still *presents* (just without the morph), so there's no functional fallback branch to write — worst case is a cross-fade instead of a zoom. (Availability is settled: these are iOS 18.0 APIs, app floor 18.6 → always present; the compiler is the arbiter, no `#available` fence.)
- **Parallax:** prototype scrolls the art under the scrim. Keep v1 static (scrim only); add parallax via `.visualEffect` + scroll geometry (no `GeometryReader`, per `docs/swiftui.md`) only if cheap.
- **Directions with null address:** fall back to a `name, city, state` Maps query; never show an empty address row.
- **Cancelled/sold-out over a poster:** cancelled desaturates (as the ticket already does); sold-out keeps the pill. Confirm both read on the poster, per the prototype's open question.

---
status: exploration
source: sharing brainstorm 2026-07-18 — deep links, share cards, App Clip assessment
captured: 2026-07-18
related: docs/ideas/on-tour-share-cards.html, docs/plans/474-touring-soon-tab.md, docs/plans/on-tour-poster-detail.md, docs/ideas/spotlight-app-entities.md
---

# On Tour sharing — deep links, share cards, and the App Clip question

A listener finds a show in the On Tour tab and sends it to a friend. This doc designs that loop: what URL gets shared, what the recipient sees in Messages and elsewhere, how the app routes the link, what the no-app fallback is, and whether an App Clip belongs in the picture. The visual half — every card mocked per surface — is `docs/ideas/on-tour-share-cards.html`.

## TL;DR

**Ship universal links + a Cloudflare-Worker share page first; hold the App Clip until the share page's analytics prove the no-app tap volume.** One canonical URL (`https://wxyc.org/shows/<id>`) serves three audiences: app owners deep-link into the On Tour poster detail; everyone else lands on an OG-tagged share page with the poster, a ticket link, a working live-stream player, and a Smart App Banner. The share *card* in Messages/WhatsApp/Slack is fully authored by that page's OG tags — recommendation: a per-show generated poster image mirroring the app's poster hero (variant B in the HTML), with a static wordmark card as the day-one placeholder. The App Clip is real but appointed to Phase 3: verified against Apple docs, it upgrades exactly one surface (the iMessage no-app card, sender-in-contacts only) and **cannot play background audio** — it's a conversion vehicle, not portable radio.

## What exists today (verified 2026-07-18)

| Fact | Where |
|---|---|
| `wxyc://` scheme with a canonical parser (`play`, `playcut/<id>`), built to grow cases | `Shared/Intents/Sources/Intents/WXYCDeepLink.swift` |
| `.onOpenURL` + `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` already registered — the exact arrival point for universal links | `WXYC/iOS/AppLifecycleModifier.swift:38-46` |
| Typed open-message precedent (`PlaycutOpenMessage` via `MainActorNotificationMessage`) — note: posted but no observer wired yet | `Shared/Intents/Sources/Intents/PlaycutOpenMessage.swift` |
| No associated-domains entitlement on any target; no `applinks` AASA anywhere in the org (dj-site's AASA is `webcredentials`-only, but proves the Workers + correct-content-type pattern) | `WXYC/Entitlements/WXYC.entitlements`; `dj-site/app/.well-known/apple-app-site-association/route.ts` |
| wxyc.org = static Next.js export on GitHub Pages, but the **zone is on Cloudflare** (DNS currently gray-cloud to GH Pages IPs); no AASA served today (404) | `website/next.config.js`, `dig wxyc.org NS` |
| `GET /concerts` is the only concerts read: list-only, anonymous-session JWT required, default-windowed to `starts_on >= today` | `Backend-Service/apps/backend/routes/concerts.route.ts` |
| Concert PK is a serial int; re-scrapes upsert on `(source, source_id)`, so ids survive re-scrapes **except** triangle-shows `hash:`-tier events (no external id/URL), which can re-insert under a new id | `Backend-Service/shared/database/src/schema.ts:2200-2291`, `jobs/triangle-shows-etl/writer.ts:158-201` |
| Past concerts are never deleted — tombstoned (`removed_at`) and windowed out, so a by-id read can serve "this show's passed" forever | `Backend-Service/apps/backend/services/concerts.service.ts:191-200` |
| `Concert.image_url` exists but is null for most shows; the app already ships a deterministic `PosterGradient` fallback | `Shared/Concerts/Sources/Concerts/PosterGradient.swift` |
| Contract drift: `api.yaml` now carries `Concert.event_url` (required-nullable) but the iOS model still documents it as missing (`ctaURL` awaits the BS#1609 revert) — adjacent cleanup, not sharing-blocking | `wxyc-shared/api.yaml:2169-2175` vs `Shared/Concerts/Sources/Concerts/Concert.swift:188-200` |

## The link

**Canonical:** `https://wxyc.org/shows/4821`. Human word ("shows", matching the tab's voice) rather than the API's "concerts"; the raw string appears in every SMS fallback and read-aloud, so it should scan as a sentence. An optional readable suffix (`/shows/4821-jessica-pratt`) is tolerated — parser reads the leading integer, Worker canonicalizes. The id is Backend `concerts.id`; the hash-tier instability above is accepted for v1 because the failure mode is graceful (below) and hash-tier events are the minority. If breakage shows up in analytics, the fix is a stable share slug minted server-side, not a URL redesign.

**Hosting — DECIDED 2026-07-18: the apex.** Proxy the apex record (and the `www` CNAME, so both flip together) through Cloudflare and add Worker routes owning exactly `/shows/*` and the exact path `/.well-known/apple-app-site-association` — never a `/.well-known/*` wildcard, which would intercept the `acme-challenge` requests GitHub's Let's Encrypt renewal for the origin cert depends on. Everything else passes through to GitHub Pages untouched. This puts the AASA under the domain listeners already trust, and pre-stakes the ground for later universal links (playcut shares, Spotlight entities). `share.wxyc.org` was the considered no-touch alternative; passed over because its costs are permanent (the string in every message, a second link registry forever) while the apex's risks are front-loaded and reversible in seconds (the proxy toggle). dj-site's OpenNext-on-Workers deploy is the in-org precedent for serving an AASA with correct `Content-Type`. Cutover checklist under Phasing.

**AASA** (served by the Worker at `/.well-known/apple-app-site-association`, no redirect, `application/json`):

```json
{
  "applinks": { "details": [{ "appIDs": ["92V374HC38.org.wxyc.iphoneapp"], "components": [{ "/": "/shows/*" }] }] },
  "appclips": { "apps": ["92V374HC38.org.wxyc.iphoneapp.Clip"] }
}
```

(`appclips` lands only in Phase 3; `webcredentials` stays dj-site's concern on its own domain. Android later: the same Worker serves `assetlinks.json` and the same URLs deep-link the Android app — no new link format.)

## iOS: emitting the link

Share affordances (mocked in §6 of the HTML): a share button in `ConcertDetailView`'s chrome (top-right, mirroring the back button's frosted circle) and a long-press context menu on `ConcertRow` (Share Show / Get Tickets / Directions). Both drive one `ShareLink`:

- **Item = the bare URL, nothing else.** Prose lives in `SharePreview("Jessica Pratt at Cat's Cradle", image: posterThumb)` — the share-sheet header only. A bare-link message is what lets iMessage swap in the App Clip card later; concatenated text would permanently pin us to the plain preview.
- `posterThumb`: `ImageRenderer` snapshot of the poster gradient (or `image_url` when present) so the sheet preview matches the card the recipient gets.
- URL construction belongs on `Concert` in `Shared/Concerts` (`concert.shareURL`), unit-tested, so widgets/Spotlight surfaces can reuse it.
- Analytics per house idiom: `ConcertShareInitiated(surface: detail|row)`; no recipient-side identity, consistent with the likes privacy stance.

## iOS: receiving the link

1. **Entitlement:** `com.apple.developer.associated-domains` += `applinks:wxyc.org` on the app target (Debug too).
2. **Parser:** `WXYCDeepLink` gains `case concert(Int)` and a second initializer for universal links (`init?(universalLink:)` accepting `https://wxyc.org/shows/<id>[-slug]`), plus the `wxyc://concert/<id>` scheme alias for internal surfaces. The enum's file header already anticipates exactly this growth.
3. **Arrival:** `AppLifecycleModifier.handleUserActivity` handles `NSUserActivityTypeBrowsingWeb` by parsing `userActivity.webpageURL` through the new initializer; `handleURL` picks up the scheme alias. Both post a typed `ConcertOpenMessage(concertID:)` — the `PlaycutOpenMessage` shape. Unlike the playcut message, wire the observer now: `RootTabView` observes, flips `selectedPage = .onTour`, and hands the pending id to `OnTourTabView`.
4. **Resolution, in order:** find the id in the loaded `OnTourModel` window → present `ConcertDetailView` (zoom from the row when visible). Miss → fetch `GET /concerts/:id` (new endpoint, below) and present the detail directly — including past/tombstoned shows, which render with a "this one's passed" treatment instead of the CTA row. Hard miss (deleted, malformed) → land on the tab with a quiet "couldn't find that show" notice. Cold launch holds the pending id until the model's first load completes.
5. Analytics: `ConcertDeepLinkOpened(source: universalLink|scheme, resolution: window|byID|missed)` — the funnel's receiving half.

## The share page (the floor every surface degrades to)

A Cloudflare Worker route `GET /shows/:id`: fetches the concert from Backend-Service, renders one screen of static HTML — poster hero (real `image_url` or the same deterministic gradient, ported), artist/support/venue/date/price/age/status, Get Tickets (`ticket_url`), venue page (`event_url`), directions, an `<audio>` element on the Icecast stream ("Listen to WXYC — live"), and "Open in the WXYC app". Plus the tags that author every card: `og:title` ("Jessica Pratt at Cat's Cradle — WXYC"), `og:description` (date · doors · price · age · station credit), `og:image`, `twitter:card`, and `<meta name="apple-itunes-app" content="app-id=…">` for the Smart App Banner. Cache at the edge (~5 min) — share spikes never touch the API. Past show → "This one's passed — here's what's coming up" with a link to the tab's window. PostHog JS on the page (`share_page_viewed {concert_id, os}`, `share_page_cta_tapped {cta}`) is the instrumentation that later adjudicates the App Clip.

**Backend prerequisite — the one real API change:** a public, cacheable `GET /concerts/:id` (no session requirement; the current list route requires an anonymous JWT, which a web page can't mint sanely). Ignores the date window, serves tombstoned rows with their status. Contract lands in `wxyc-shared/api.yaml` first, per discipline. This endpoint also serves the app's deep-link fallback in §"receiving", so it's Phase 1, not web-only. Coordinate the filing with the On Tour epic (BS#1588) rather than as a stray.

**OG image:** day one, a static WXYC wordmark card (variant A in the HTML). Fast follow: variant B — a per-show 1200×630 render of the poster hero (PosterGradient + oversized initial + artist/venue/date type) via `workers-og`/satori on the same Worker, so what you tap in the bubble is what the app opens into. Variant C (the amber ticket stub) was considered and held: it dies at thumbnail sizes and fights dark bubble chrome; its perforation rule gets donated to B's date block.

## What renders where (mechanics verified against Apple docs)

The full mocked matrix is §7 of the HTML. The compressed truth: **OG tags cover seven of eight rows** — iMessage rich links (both app states in Phase 1), WhatsApp/Slack/Discord unfurls, Mail/Notes/AirDrop, SMS-after-tap. The eighth row is the iMessage App Clip card, which requires Phase 3 and renders only when the sender is in the recipient's contacts, always with the *default* App Clip experience's metadata (header 1800×1200, title ≤30 chars, subtitle ≤56 chars, action ∈ {Open, View, Play}). In-app browsers (WhatsApp/Slack) don't fire universal links — the share page's "Open in the WXYC app" button covers that hop.

## The App Clip, assessed honestly

**What it would be:** `org.wxyc.iphoneapp.Clip` — the poster detail + tickets CTA + a foreground "listen while you look" player + "Get WXYC" (`SKOverlay`). Reuses `Shared/Concerts` wholesale and a slim playback path; excludes Wallpaper/Metal, CarPlay, widgets, Intents.

**Verified constraints that size the bet:**

- **No Background Modes.** The stream stops the moment the clip is backgrounded or the phone locks. The radio's core loop physically cannot live in a clip — it can only *demo*. This is the finding that demoted the clip from Phase 1.
- Also unavailable: AppIntents (no Siri), MediaPlayer (no lock-screen now-playing — moot given the above), and the long framework blocklist. When-in-use location only; ephemeral notifications (8 h) if ever wanted.
- **Size:** 100 MB uncompressed post-thinning for iOS 17+ digital-only invocations — a poster page plus an MP3 stream fits with room to spare. Staying under 15 MB would additionally unlock **physical invocations: App Clip Codes printed on venue flyers and station merch** — a very WXYC object, and the strongest reason the clip stays on the roadmap at all.
- **Reach:** upgrades the iMessage no-app bubble (contacts-only) and adds the Safari `app-clip-display=card` sheet. Every other surface is untouched — the share page keeps doing the work.
- **Costs:** a second target + provisioning + ASC default-experience config + review surface + keeping clip and app renderings of the detail from drifting. App Group handoff (the existing `group.wxyc.iphone` machinery pattern) carries the pending show id through install so the full app opens where the clip left off.

**Verdict:** genuinely good fit *as a conversion vehicle* — a native, beautiful, zero-install landing for the single most common share (friend texts friend) — but only worth its carrying cost if that cell is hot. Phase 1's share-page analytics (`share_page_viewed` where `os=iOS`) measures exactly that cell's volume. Decide at Phase 3 with numbers; prior art exists (Eter's station-sharing clip) if we go.

## Phasing (ticket sketch — nothing filed yet)

| Phase | Work | Repos |
|---|---|---|
| 1a | Contract: `GET /concerts/:id` (public, cacheable, windowless) in `api.yaml`; BS implementation | wxyc-shared, Backend-Service |
| 1b | Apex cutover (checklist below), then Worker: `/shows/:id` share page + OG tags (static image A) + AASA `applinks` + edge cache + page analytics | new (`wxyc-share`?) or website-adjacent |
| 1c | iOS: `concert.shareURL` + ShareLink affordances (detail chrome, row context menu) + associated-domains + `WXYCDeepLink.concert` + `ConcertOpenMessage` routing + passed-show detail state + analytics. Ships after 1b is live so the AASA validates on update | wxyc-ios-64 |
| 2 | OG image worker (variant B, per-show poster render); "Add to Calendar" affordance (`EKEvent` from `starts_at`/`doors_at`) | Worker; wxyc-ios-64 |
| 3 | App Clip target + ASC default experience + `appclips` AASA key + App Group handoff — **gated on Phase 1 analytics** | wxyc-ios-64, Worker |

1c is a normal-sized iOS PR; 1a/1b are small and land first. Android parity is a later consumer of the same URLs (assetlinks.json + intent filters), zero redesign.

### 1b stage 1 — apex cutover checklist

Proxying is per-record and all-or-nothing for apex traffic, so the flip is its own stage, done with **no Worker routes attached**, soaked, then built on. Rollback at any point is the orange→gray toggle (seconds, minus DNS TTL).

1. **Preflight (zone):** confirm zone-admin access; inventory apex + `www` records; check the zone-wide SSL/TLS mode — it must be **Full (strict)** *before* flipping (Flexible = redirect loop against GH Pages' enforce-HTTPS; the mode is zone-wide, so verify the current setting that dj.wxyc.org already runs under rather than assuming). Confirm transforms (Rocket Loader, minification, email obfuscation) are off or scoped off for the apex, and that Bot Fight Mode / WAF rules won't challenge `AASA-Bot`, `CFNetwork`, or OG unfurl bots (WhatsApp/Slack/Discord) — a challenged AASA fails silently.
2. **Flip:** proxy apex + `www` in one change. Verify immediately: homepage serves via Cloudflare (`cf-ray` header), edge cert valid, no redirect loop, deep pages render (blog, archive, specialty-shows), a website-repo deploy propagates.
3. **Soak a few days**; expect and ignore the GitHub Pages repo-settings domain-check warning (leave a README note in the website repo so nobody "fixes" the DNS back). Re-verify after GitHub's next origin-cert renewal cycle (current cert expires 2026-09-19; the ACME path must keep flowing through untouched).
4. **Stage 2:** deploy the Worker + the two exact routes; validate the AASA with curl and Apple's CDN view (`https://app-site-association.cdn-apple.com/a/v1/wxyc.org`); only then ship the iOS entitlement (1c).

## Resolved decisions

- **2026-07-18 — Apex, not subdomain.** Links are `https://wxyc.org/shows/<id>`; the AASA lives on the apex and becomes the org's universal-link registry. Decided on the asymmetry: apex risk is front-loaded, inspectable, reversible in seconds; subdomain costs (URL quality, a permanent second registry, the apex question merely deferred) are forever. `/shows/` path name kept despite the radio-show ambiguity (`archive/specialty-shows`) — read-aloud naturalness wins; revisit only if a programs section ever claims the word.

## Open questions
- **Hash-tier id breakage:** accept-with-fallback (current position) vs. minting stable share slugs at the backend. Revisit only if `ConcertDeepLinkOpened(resolution: missed)` shows real volume.
- **Where does the Worker live** — a new tiny repo, or a `share/` corner of an existing one? (It wants CI and a CLAUDE.md either way.)
- **Does "Share Show" belong on the Box Office ticket in Playcut Detail too?** Same `shareURL`, same sheet — cheap, but widens the surface; decide at 1c review.

# Configuration, Signing & Extensions

## Configuration

App configuration (PostHog API key, API base URL, request-o-matic URL) is managed by `AppConfiguration` in the AppServices package. Values are hardcoded as defaults and optionally fetched from the backend `/config` endpoint at launch. Confidential API credentials (Discogs, Spotify) are no longer embedded in the app; those calls are proxied through Backend-Service behind anonymous device session auth.

## Code Signing

- Development Team: `92V374HC38`
- Code Sign Style: Automatic
- All targets (including extensions) must have `DevelopmentTeam` in their TargetAttributes

### Extension Targets

- **Request Share Extension**: Share sheet integration for sharing songs
- **NowPlayingWidget**: Home screen widget showing current track
- **CarPlay**: CarPlay scene delegate in main app

## Widget Considerations

- Widget refresh budget: 40-70 updates/day
- Foreground refreshes don't count against budget
- Background refresh scheduled every 15 minutes
- OpenNSFW model seeded to shared container for widget access

## App Store Previews

App Store screenshots and preview assets live in a separate project at `../app-store-previews`. Use that project when preparing assets for App Store publication.

## Minimum iOS Version

iOS 18.6 (based on SDK version in built app)

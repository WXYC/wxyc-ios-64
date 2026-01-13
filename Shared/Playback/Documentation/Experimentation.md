# Experimentation & Feature Flags

This document details the feature flags used for A/B testing player implementations and the logic governing their selection.

## Feature Flag: `experiment_player_controller`

This flag controls which audio player implementation is selected for the user.

### 1. Variant Mapping

The experiment returns a **String** value (the variant key). This is mapped to the internal `PlayerControllerType` enum in `PlayerControllerType.swift`.

| Variant Key (PostHog) | PlayerControllerType (Swift) | Description |
| :--- | :--- | :--- |
| `RadioPlayer` | `.radioPlayer` | Uses `AVPlayer` with custom buffering logic. |
| `MP3Streamer` | `.mp3Streamer` | Uses URLSession + AudioToolbox for MP3 decoding (Current Default). |

*Note: If the flag returns a value not listed here, or is missing, the app falls back to `.mp3Streamer`.*

### 2. Logic & Priority

The selection logic is strictly defined in `PlayerControllerType.loadPersisted()`. The priority order is:

1.  **Manual Debug Override** (`High Priority`)
    *   **Source:** `UserDefaults` key `debug.isPlayerControllerManuallySelected` + `debug.selectedPlayerControllerType`.
    *   **Set via:** Debug View -> Player selection.
    *   **Purpose:** Allows developers/QA to force a specific player, ignoring any running experiments.

2.  **PostHog Experiment / Feature Flag**
    *   **Source:** `PostHogSDK.shared.getFeatureFlag("experiment_player_controller")`.
    *   **Condition:** Only checked if *no* manual override exists.
    *   **Purpose:** Assigns the user to a test cohort (A/B testing).

3.  **Local Default** (`Fallback`)
    *   **Source:** `PlayerControllerType.defaultType`.
    *   **Value:** `.mp3Streamer`.
    *   **Purpose:** Safety fallback if network fails, flag is missing, or experiment is turned off.

### 3. Lifecycle & Timing

*   **Initialization:** The check happens immediately when `PlaybackControllerManager` is initialized (Singleton instantiation).
    *   Code Path: `PlaybackControllerManager.init()` -> `PlayerControllerType.loadPersisted()`.
*   **App Launch:** Since `PlaybackControllerManager.shared` is typically accessed early (e.g., in UI setup or AppDelegate), the player type is locked in shortly after launch.
*   **Updates:**
    *   The player selection is **sticky** for the session.
    *   If PostHog fetches new flags in the background *during* a session, the active player **does not** change immediately.
    *   The new flag value will take effect on the **next app launch** (or if the app is killed and restarted).

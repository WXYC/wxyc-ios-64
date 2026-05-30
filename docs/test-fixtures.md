# Example Music Data for Tests

WXYC is a freeform station. When creating test fixtures or mock data, use representative artists instead of mainstream acts like Queen, Radiohead, or The Beatles. The canonical data source is `wxyc-shared/src/test-utils/wxyc-example-data.json`. See the reference table in the org-level CLAUDE.md.

When populating `Playcut.stub()` calls or `FlowsheetEntry` literals, use values like these instead of "Test Artist" / "Test Song" / "Test Album":

```swift
// Playcut.stub() examples
Playcut.stub(songTitle: "In a Sentimental Mood", artistName: "Duke Ellington & John Coltrane", releaseTitle: "Duke Ellington & John Coltrane", labelName: "Impulse Records")
Playcut.stub(songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA", labelName: "Sonamos")
Playcut.stub(songTitle: "Aluminum Tunes", artistName: "Stereolab", releaseTitle: "Aluminum Tunes", labelName: "Duophonic")
Playcut.stub(songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", labelName: "Matador Records")
Playcut.stub(songTitle: "Back, Baby", artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again", labelName: "Drag City")
Playcut.stub(songTitle: "Call Your Name", artistName: "Chuquimamani-Condori", releaseTitle: "Edits", labelName: nil)

// FlowsheetEntry example
FlowsheetEntry(id: 1, show_id: 10, album_id: 100,
    artist_name: "Juana Molina", album_title: "DOGA",
    track_title: "la paradoja", record_label: "Sonamos",
    rotation_id: nil, rotation_play_freq: nil,
    request_flag: false, message: nil,
    play_order: 1, add_time: "2025-11-01T22:15:00.000Z")
```

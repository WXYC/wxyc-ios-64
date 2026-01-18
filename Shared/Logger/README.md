# Logger

A unified logging API for the WXYC app, wrapping `os.Logger` for consistent debug output across iOS, watchOS, and macOS.

## Features

- **Multi-destination output**: Logs to Console.app (via OSLog), Xcode console, and persistent files
- **Log levels**: Debug, Info, Warning, and Error with filtering support
- **Categories**: Organize logs by feature area (Playback, Artwork, Network, etc.)
- **Configurable filtering**: Set global or per-category minimum log levels
- **Log persistence**: Daily log files with automatic compression and 7-day retention
- **Export support**: Retrieve logs for attaching to feedback emails

## Usage

### Basic Logging

Use the global `Log` instance with callable syntax:

```swift
import Logger

// Simple logging
Log(.info, "App launched")

// With category
Log(.debug, category: .playback, "Starting audio stream")

// Error logging
Log(.error, category: .network, "Failed to fetch playlist: \(error)")
```

### Log Levels

```swift
Log(.debug, "Detailed debugging information")
Log(.info, "General information")
Log(.warning, "Something unexpected but recoverable")
Log(.error, "Something went wrong")
```

### Categories

Built-in categories:

- `.general` (default)
- `.playback`
- `.artwork`
- `.caching`
- `.network`
- `.ui`
- `.wallpaper`

Create custom categories:

```swift
extension Category {
    static let widget = Category(rawValue: "Widget")
}

Log(.info, category: .widget, "Widget refreshed")
```

### Filtering

Configure minimum log levels to reduce noise:

```swift
// Set global minimum (filters out debug messages)
LoggerConfiguration.shared.minimumLevel = .info

// Set category-specific minimum
LoggerConfiguration.shared.setMinimumLevel(.warning, for: .network)

// Clear category override
LoggerConfiguration.shared.clearMinimumLevel(for: .network)
```

### Log Retrieval

Export logs for debugging or user feedback:

```swift
// Get today's log
if let (name, data) = Logger.fetchLogs() {
    // Attach to email, upload, etc.
}

// Get all available logs (including compressed)
let allLogs = Logger.fetchAllLogs()
```

## Log Output Format

Each log entry includes:

```
2025-01-18 14:30:45.123 FileName.swift:42 functionName() [Category/LEVEL] Message
```

## File Storage

- Location: `<CachesDirectory>/logs/`
- Naming: `YYYY-MM-DD.log`
- Previous days' logs are automatically compressed to `.log.zip`
- Logs older than 7 days are deleted

## Thread Safety

Logger is fully thread-safe and `Sendable`-compliant. File writes are isolated to a dedicated `@globalActor` to avoid blocking the caller.

## Requirements

- iOS 18.0+
- watchOS 8.0+
- macOS 15.0+
- Swift 6.2+

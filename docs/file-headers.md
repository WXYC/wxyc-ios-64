# File headers

All Swift and Metal files (except `Package.swift`) must have a standard header comment:

```swift
//
//  Filename.swift
//  PackageName
//
//  Brief description of what this file does and how it fits into its package.
//
//  Created by Author Name on MM/DD/YY.
//  Copyright © YYYY WXYC. All rights reserved.
//
```

When creating new files:
- Use today's date for "Created by"
- Use the current year for copyright
- The package name should match the Swift package or "WXYC" for app files
- Always include a description explaining the file's purpose

The pre-commit hook (`scripts/hooks/header-check.sh`) validates headers and can use Claude to generate missing descriptions automatically.

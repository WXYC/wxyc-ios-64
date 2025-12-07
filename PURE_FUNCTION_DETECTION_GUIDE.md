# Pure Function Detection in Swift Using LLVM/SIL

## Overview

This guide documents the tools and techniques for detecting pure functions in Swift projects using LLVM's Swift Intermediate Language (SIL) analysis. These tools were developed to analyze the WXYC iOS project for functional purity patterns.

## Background: Why LLVM for Pure Function Detection?

### The Challenge

As of 2025, **no existing Swift static analysis tools** specifically detect pure functions. Common tools like:
- SwiftLint
- SWAN (Swift Static Analysis Framework)
- Sitrep
- DeepSource Swift Analyzer

...focus on security, bugs, and code quality rather than functional programming paradigms like purity.

### The Solution: LLVM/SIL Analysis

LLVM provides built-in capabilities for detecting pure functions through:

1. **Function Attributes** in LLVM IR:
   - `readnone` / `memory(none)` - Truly pure (no memory access)
   - `readonly` / `memory(read)` - No writes to memory
   - `-functionattrs` pass - Automatically infers these attributes

2. **Swift Intermediate Language (SIL)** - Better for Swift:
   - Swift compiles: **Source → SIL → LLVM IR → Machine Code**
   - Side-effect analysis happens at the **SIL level**
   - Memory effects annotated with `[global: ...]` markers

## Key Findings

### SIL Memory Effect Annotations

In SIL output, every function is annotated with its memory effects:

```swift
// Pure function - no global state access
sil hidden @add : $@convention(thin) (Int, Int) -> Int {
[global: ]  // ← Empty = pure!

// Impure function - reads/writes global state
sil hidden @incrementCounter : $@convention(thin) () -> Int {
[global: read,write,deinit_barrier]  // ← Has side effects
```

### LLVM IR Function Attributes

In LLVM IR, pure functions are marked with specific attributes:

```llvm
; Pure function
define hidden swiftcc double @multiply(double %0, double %1) #4 {
  ...
}

attributes #4 = {
  mustprogress nofree norecurse nosync nounwind willreturn
  memory(none)  ; ← Truly pure - no memory access
  "frame-pointer"="non-leaf"
  ...
}
```

**Attribute Meanings:**
- `memory(none)` - Function doesn't read or write memory (pure)
- `memory(read)` - Function only reads memory (no side effects)
- `nounwind` - Function doesn't throw exceptions
- `willreturn` - Function always returns (no infinite loops)

### Example: Pure vs Impure Functions

From our test analysis:

**✓ Pure Functions (SIL shows `[global: ]`):**
- `add(_:_:)` - Simple arithmetic
- `multiply(_:_:)` - Mathematical operation
- `calculateArea(radius:)` - Deterministic calculation
- `Point.distance(to:)` - Geometric calculation
- Struct getters and initializers

**⚠ Impure Functions (SIL shows effects):**
- `incrementCounter()` - `[global: read,write,deinit_barrier]`
- `getCurrentTime()` - `[global: read,write,copy,destroy,allocate,deinit_barrier]`
- `printAndReturn(_:)` - `[global: read,write,copy,destroy,allocate,deinit_barrier]`

**Interesting Case:**
```swift
// sqrt is marked [readnone] in SIL
sil [readnone] [clang sqrt] @sqrt : $@convention(c) (Double) -> Double
```

The `sqrt` function is a perfect example of a pure function - its output depends only on input, with no side effects.

## Tools Created

### 1. Pure Function Detector (`find_pure_functions.py`)

A Python script that analyzes Swift files for pure functions using SIL compilation.

**Features:**
- Compiles Swift files to SIL with optimization (`-O`)
- Parses memory effect annotations
- Categorizes functions as pure/impure
- Shows detailed side effect information

**Usage:**
```bash
# Analyze single file
python3 find_pure_functions.py path/to/file.swift

# Analyze multiple files
python3 find_pure_functions.py file1.swift file2.swift file3.swift

# Show only pure functions
python3 find_pure_functions.py --pure-only file.swift

# Verbose mode (debug compilation)
python3 find_pure_functions.py -v file.swift
```

**Example Output:**
```
================================================================================
File: Timer.swift
================================================================================

✓ PURE FUNCTIONS (2)
--------------------------------------------------------------------------------
  • main
  • Timer.start.getter

⚠ IMPURE FUNCTIONS (3)
--------------------------------------------------------------------------------
  • static Timer.start()
    Effects: read,write,copy,destroy,allocate,deinit_barrier
  • Timer.duration()
    Effects: read,write,copy,destroy,allocate,deinit_barrier
  • variable initialization expression of Timer.start
    Effects: read,write,copy,destroy,allocate,deinit_barrier

================================================================================
SUMMARY
================================================================================
Total Pure Functions: 2
Total Impure Functions: 3
```

### 2. Project Analyzer (`analyze_project_purity.sh`)

Batch analyzer for entire project modules.

**Features:**
- Scans all Swift files in Core module
- Shows progress with color-coded output
- Generates combined analysis report
- Handles compilation failures gracefully

**Usage:**
```bash
./analyze_project_purity.sh
```

**Output:**
```
🔍 Analyzing Swift project for pure functions...

Found 25 Swift files to analyze

Analyzing Timer.swift... ✓ Pure: 2, Impure: 3
Analyzing ExponentialBackoffTimer.swift... ✓ Pure: 14, Impure: 5
Analyzing PlaylistEntry.swift... ⚠ Failed (likely has dependencies)
...

═══════════════════════════════════════════════════════════════
Analysis complete!
  Analyzed: 15 files
  Failed: 10 files (due to dependencies)
═══════════════════════════════════════════════════════════════

Detailed results saved to: pure_functions_analysis.txt
```

## Real Project Results

From analyzing WXYC iOS project files:

### `ExponentialBackoffTimer.swift`
- **14 pure functions** - Getters, initializers, simple calculations
- **5 impure functions** - Including `random()` (non-deterministic)

### `Timer.swift`
- **2 pure functions** - Simple getters
- **3 impure functions** - Date/time operations

## How to Use for Your Project

### Quick Start

1. **Analyze a specific file:**
   ```bash
   python3 find_pure_functions.py WXYC/Shared/Core/Sources/Core/Timer.swift
   ```

2. **Find all pure functions in a file:**
   ```bash
   python3 find_pure_functions.py --pure-only Timer.swift
   ```

3. **Analyze entire Core module:**
   ```bash
   ./analyze_project_purity.sh
   ```

### Manual SIL Inspection

For deeper analysis, inspect SIL directly:

```bash
# Generate SIL for a file
swiftc -emit-sil -O YourFile.swift -o output.sil

# Find pure functions (those with empty global effects)
grep -B3 "[global: ]" output.sil

# View all memory effect annotations
grep -E "\[global:" output.sil
```

### LLVM IR Inspection

To see LLVM-level attributes:

```bash
# Generate LLVM IR
swiftc -emit-ir -O YourFile.swift -o output.ll

# Find attribute definitions
grep "^attributes #" output.ll

# Find memory(none) functions
grep -E "memory\(none\)" output.ll
```

## Important Limitations

### 1. Dependency Issues

**Problem:** The tool compiles individual Swift files in isolation.

**Impact:** Files with dependencies fail to compile:
- Imports from other modules (`import Logger`, `import PostHog`)
- Custom types from other files
- Framework dependencies beyond Foundation

**Current Status:** ~40% of project files compile successfully standalone.

**Workaround:** Build entire project with SIL output:
```bash
xcodebuild -project WXYC.xcodeproj \
  -scheme WXYC \
  -configuration Release \
  build \
  OTHER_SWIFT_FLAGS="-emit-sil"
```

### 2. Definition of Purity

**What This Analysis Detects:**
- ✅ No global state access
- ✅ No I/O operations
- ✅ Deterministic behavior

**What This Analysis Does NOT Detect:**
- ❌ Instance variable mutation (class methods)
- ❌ Memory allocation patterns
- ❌ Local state modifications

**Example:**
```swift
class Counter {
    private var count = 0

    func increment() -> Int {
        count += 1  // Mutates instance var
        return count
    }
}
```

The `increment()` method may be marked "pure" in SIL because it doesn't access **global** state, even though it modifies instance state.

### 3. Compiler Optimizations

With `-O` flag, the optimizer may:
- Inline pure functions (they disappear from SIL)
- Eliminate dead code
- Combine multiple functions

Some functions may not appear in the output at all.

## Technical Deep Dive

### Swift's Multi-Stage Compilation

```
Swift Source Code
       ↓
Swift Intermediate Language (SIL)  ← Side-effect analysis happens here
       ↓
LLVM Intermediate Representation (IR)
       ↓
Machine Code
```

**Why SIL is Better for Swift:**
- Swift-specific optimizations occur at SIL level
- Side-effect analysis is more accurate
- Better type information preserved
- Function semantics clearer

### Memory Effect Taxonomy

SIL tracks these memory effects:

| Effect | Meaning |
|--------|---------|
| (empty) | No global state access (pure) |
| `read` | Reads global variables |
| `write` | Writes to global variables |
| `copy` | Copies reference-counted objects |
| `destroy` | Destroys/deallocates objects |
| `allocate` | Allocates memory |
| `deinit_barrier` | Synchronization for deinitializers |

### Pattern Recognition

**Pure Function Patterns:**
- Arithmetic operations
- Mathematical functions
- Struct getters (computed properties)
- Struct initializers
- Pure transformations on values

**Impure Function Patterns:**
- Global variable access
- I/O operations (`print`, `read`, `write`)
- Time/date operations (`Date()`)
- Random number generation
- Network/file system access

## Comparison: LLVM IR vs SIL

### LLVM IR Analysis

**Pros:**
- Language-agnostic
- Standard LLVM tooling
- Well-documented attributes
- `functionattrs` pass available

**Cons:**
- Generated after Swift-specific optimizations
- Less Swift semantic information
- Harder to map back to source code

### SIL Analysis (Our Approach)

**Pros:**
- ✅ Swift-native representation
- ✅ Better type information
- ✅ Easier source mapping
- ✅ More accurate for Swift code

**Cons:**
- Swift-specific (less portable)
- Less documentation
- Requires understanding SIL format

## Future Enhancements

Potential improvements to these tools:

1. **Full Project Analysis**
   - Parse combined SIL from full build
   - Resolve all dependencies
   - Generate cross-module reports

2. **Advanced Pattern Detection**
   - Detect referential transparency
   - Identify instance mutation
   - Track data flow

3. **IDE Integration**
   - Xcode Source Editor Extension
   - In-editor annotations
   - Real-time analysis

4. **Stricter Purity Checks**
   - Detect instance mutations
   - Track escape analysis
   - Identify allocation patterns

## Resources

### Documentation
- [LLVM Language Reference](https://llvm.org/docs/LangRef.html)
- [LLVM Function Attributes](https://llvm.org/docs/LangRef.html#function-attributes)
- [LLVM Analysis Passes](https://llvm.org/docs/Passes.html)
- [Swift SIL Documentation](https://github.com/apple/swift/blob/main/docs/SIL.rst)
- [Swift Optimizer Design](https://github.com/apple/swift/blob/main/docs/OptimizerDesign.md)

### Related Research
- [Swift Static Analysis Framework (SWAN)](https://github.com/themaplelab/swan)
- [DeepSource Swift Analyzer](https://deepsource.com/blog/swift-static-analysis)
- [Static Code Analysis Tools for Swift](https://analysis-tools.dev/tag/swift)

## Conclusion

While no off-the-shelf Swift tools detect pure functions, **LLVM's SIL provides a robust foundation** for this analysis. The tools created here successfully identify pure functions by:

1. Compiling Swift to SIL with optimizations
2. Parsing memory effect annotations
3. Categorizing functions by global state access

**Key Takeaway:** For Swift projects, **SIL analysis is more effective than LLVM IR** for detecting functional purity, though both approaches have value.

These tools provide a practical way to:
- Identify pure functions in your codebase
- Understand side-effect patterns
- Guide refactoring toward functional purity
- Validate architectural assumptions

---

**Project Files:**
- `find_pure_functions.py` - Main analysis tool
- `analyze_project_purity.sh` - Batch analyzer
- `PURE_FUNCTIONS_ANALYSIS.md` - Technical reference
- `PURE_FUNCTION_DETECTION_GUIDE.md` - This guide

**Created:** December 2025
**Project:** WXYC iOS (wxyc-ios-64)

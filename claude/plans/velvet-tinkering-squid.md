# Event Plugin Boilerplate Reduction Plan

## Goal
Eliminate duplicate boilerplate across 33 EventPlugin implementations by providing default protocol implementations for common patterns.

**Design Principles:**
- **Protocol extensions over base classes** - Swift-native approach, opt-in overrides
- **No macros or code generation** - keep it simple, no build complexity
- **No backward compatibility code** - clean break, all plugins updated
- **Mandatory conformance** - all EventData types must conform to StandardEventData
- **Test-driven** - write tests first, verify each plugin individually

## Current State Analysis

**33 plugins** organized in 9 categories with significant boilerplate:

| Pattern | Occurrences | Boilerplate Lines |
|---------|-------------|-------------------|
| `sessionId(from:)` returning `event.sessionId` | 28/33 (85%) | ~3 lines × 28 = 84 lines |
| Identical EventData outer structure | 33/33 (100%) | ~8 lines × 33 = 264 lines |
| Simple field-passthrough transform | 13/33 (40%) | varies |

**Total estimated boilerplate:** ~400-500 lines across all plugins

### Plugin Complexity Breakdown
- **Simple** (13 plugins): Direct field passthrough, no custom logic
- **Medium** (15 plugins): Fallback logic, computed properties, or field aliasing
- **Complex** (5 plugins): Custom parsing, nested structures (ToolEndPlugin, SubagentEventPlugin, etc.)

## Target State

### 1. StandardEventData Protocol
Provides common fields that 100% of plugins share:

```swift
/// Base protocol for event data with standard fields.
/// Plugins conform to this for default sessionId extraction.
protocol StandardEventData: Decodable, Sendable {
    var type: String { get }
    var sessionId: String? { get }
    var timestamp: String? { get }
}
```

### 2. Default sessionId Implementation
Protocol extension provides default for 85% of plugins:

```swift
extension EventPlugin where EventData: StandardEventData {
    static func sessionId(from event: EventData) -> String? {
        event.sessionId
    }
}
```

### 3. Result After Refactoring

**Before (typical plugin - 45 lines):**
```swift
enum TextDeltaPlugin: EventPlugin {
    static let eventType = "agent.text_delta"

    struct EventData: Decodable, Sendable {
        let type: String
        let sessionId: String?
        let timestamp: String?
        let data: DataPayload

        struct DataPayload: Decodable, Sendable {
            let delta: String
            let messageIndex: Int?
        }
    }

    struct Result: EventResult {
        let delta: String
        let messageIndex: Int?
    }

    static func sessionId(from event: EventData) -> String? {
        event.sessionId  // BOILERPLATE - identical in 28 plugins
    }

    static func transform(_ event: EventData) -> (any EventResult)? {
        Result(delta: event.data.delta, messageIndex: event.data.messageIndex)
    }
}
```

**After (same plugin - 38 lines, ~15% reduction):**
```swift
enum TextDeltaPlugin: EventPlugin {
    static let eventType = "agent.text_delta"

    struct EventData: StandardEventData {  // Conform to StandardEventData
        let type: String
        let sessionId: String?
        let timestamp: String?
        let data: DataPayload

        struct DataPayload: Decodable, Sendable {
            let delta: String
            let messageIndex: Int?
        }
    }

    struct Result: EventResult {
        let delta: String
        let messageIndex: Int?
    }

    // sessionId(from:) is now provided by default extension - REMOVED

    static func transform(_ event: EventData) -> (any EventResult)? {
        Result(delta: event.data.delta, messageIndex: event.data.messageIndex)
    }
}
```

## Files to Modify

### New/Modified Protocol File
| File | Action |
|------|--------|
| `Sources/Core/Events/Plugins/EventPlugin.swift` | ADD `StandardEventData` protocol + default `sessionId` extension |

### Plugin Files (remove sessionId boilerplate)
28 plugins will have `sessionId(from:)` removed and EventData changed to conform to `StandardEventData`:

**Streaming (5 plugins):**
- `TextDeltaPlugin.swift`
- `ThinkingDeltaPlugin.swift`
- `TurnStartPlugin.swift`
- `TurnEndPlugin.swift`
- `AgentTurnPlugin.swift`

**Tool (2 plugins):**
- `ToolStartPlugin.swift`
- `ToolEndPlugin.swift`

**Lifecycle (6 plugins):**
- `ErrorPlugin.swift`
- `InterruptedPlugin.swift`
- `CompactionPlugin.swift`
- `ModelSwitchPlugin.swift`
- `MessageDeletedPlugin.swift`
- `CostPlugin.swift`

**Session (1 plugin):**
- `ConnectedPlugin.swift` - **KEEP custom** (returns nil)

**Subagent (5 plugins):**
- `SubagentSpawnedPlugin.swift`
- `SubagentStatusPlugin.swift`
- `SubagentCompletedPlugin.swift`
- `SubagentFailedPlugin.swift`
- `SubagentEventPlugin.swift`

**PlanMode (2 plugins):**
- `PlanModeEnteredPlugin.swift`
- `PlanModeExitedPlugin.swift`

**UICanvas (5 plugins):**
- `UIRenderStartPlugin.swift`
- `UIRenderChunkPlugin.swift`
- `UIRenderCompletePlugin.swift`
- `UIRenderErrorPlugin.swift`
- `UIRenderRetryPlugin.swift`

**Browser (2 plugins):**
- `BrowserStatePlugin.swift`
- `BrowserFramePlugin.swift`

**Todo (1 plugin):**
- `TodosUpdatedPlugin.swift`

### Plugins that KEEP custom sessionId (5 plugins)
These plugins have non-standard sessionId extraction:
- `ConnectedPlugin.swift` - returns `nil` (system event)
- Any plugin with sessionId in a different location (verify during implementation)

## Implementation Steps (TDD Approach)

### Step 1: Write Tests First
Create `Tests/Core/StandardEventDataTests.swift` with comprehensive tests:

```swift
@MainActor
final class StandardEventDataTests: XCTestCase {
    // Test 1: Default sessionId extraction works
    func testDefaultSessionIdExtraction() {
        // Verify plugins using default get correct sessionId
    }

    // Test 2: Custom sessionId override works
    func testCustomSessionIdOverride() {
        // Verify ConnectedPlugin returns nil (explicit override)
    }

    // Test 3: All plugins have EventData conforming to StandardEventData
    func testAllPluginsConformToStandardEventData() {
        // Compile-time enforced, but document expectation
    }

    // Test 4: sessionId extraction for each plugin category
    func testStreamingPluginsSessionId() { ... }
    func testToolPluginsSessionId() { ... }
    func testLifecyclePluginsSessionId() { ... }
    // ... etc for all 9 categories
}
```

### Step 2: Add StandardEventData Protocol
Add to `EventPlugin.swift`:

```swift
// MARK: - Standard Event Data

/// Protocol for event data with standard session identification fields.
/// ALL EventPlugin.EventData types MUST conform to this protocol.
/// Provides default sessionId extraction - override only if returning nil or different field.
protocol StandardEventData: Decodable, Sendable {
    var type: String { get }
    var sessionId: String? { get }
    var timestamp: String? { get }
}

// MARK: - Default Implementations

extension EventPlugin where EventData: StandardEventData {
    /// Default implementation extracts sessionId from standard field.
    /// Override in plugin ONLY if sessionId should return nil or comes from different field.
    static func sessionId(from event: EventData) -> String? {
        event.sessionId
    }
}
```

### Step 3: Update ALL Plugins Systematically
For EACH of the 33 plugins:

**3a. Plugins that use default sessionId (28 plugins):**
1. Change `EventData: Decodable, Sendable` → `EventData: StandardEventData`
2. DELETE the `sessionId(from:)` function entirely
3. Verify build passes
4. Run plugin-specific tests

**3b. Plugins that need custom sessionId (5 plugins):**
1. Change `EventData: Decodable, Sendable` → `EventData: StandardEventData`
2. KEEP the explicit `sessionId(from:)` function (overrides default)
3. Add comment explaining why custom implementation is needed:
   ```swift
   // Custom: Returns nil because this is a system event, not session-specific
   static func sessionId(from event: EventData) -> String? { nil }
   ```

### Step 4: Verify Each Plugin Category
After updating each category, run incremental verification:

```bash
# After each category, build and run relevant tests
xcodebuild -project TronMobile.xcodeproj -scheme TronMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run full test suite after all plugins updated
xcodebuild -project TronMobile.xcodeproj -scheme TronMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Step 5: Final Audit
Run grep commands to verify:
1. No plugins have `Decodable, Sendable` without `StandardEventData`
2. Only expected plugins have explicit `sessionId(from:)` implementations
3. All plugins compile and tests pass

## Verification

### Build Verification
```bash
cd /Users/moose/Downloads/projects/tron/packages/ios-app

# 1. Build iOS app (must pass with zero warnings related to plugins)
xcodebuild -project TronMobile.xcodeproj -scheme TronMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build

# 2. Run full test suite
xcodebuild -project TronMobile.xcodeproj -scheme TronMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Audit Verification
```bash
# 3. Verify ALL EventData types conform to StandardEventData (no legacy Decodable, Sendable)
grep -r "EventData: Decodable, Sendable" Sources/Core/Events/Plugins/
# Expected: 0 matches (all should use StandardEventData)

# 4. Verify StandardEventData adoption count
grep -r "EventData: StandardEventData" Sources/Core/Events/Plugins/ | wc -l
# Expected: 33 (every plugin)

# 5. Count remaining explicit sessionId implementations
grep -r "func sessionId(from" Sources/Core/Events/Plugins/ | wc -l
# Expected: 5 or fewer (only plugins needing custom behavior)

# 6. List which plugins have custom sessionId (for documentation)
grep -rn "func sessionId(from" Sources/Core/Events/Plugins/
# Expected: ConnectedPlugin and any others with special requirements
```

### Functional Verification
```bash
# 7. Run the full monorepo build and test
cd /Users/moose/Downloads/projects/tron
bun run build && bun run test
```

## Outcome

| Metric | Before | After | Reduction |
|--------|--------|-------|-----------|
| `sessionId(from:)` implementations | 33 | ~5 | 28 removed (85%) |
| Lines of boilerplate | ~100 | ~15 | ~85 lines |
| Plugins using default | 0 | 28 | 28 new |
| Plugins with `StandardEventData` | 0 | 33 | 100% adoption |

**Total impact:**
- ~85 lines of duplicate code eliminated
- Consistent pattern established for all plugins
- Single source of truth for sessionId extraction
- Future plugins automatically get default behavior

# iOS App Event Plugin System

## Status: COMPLETE

## Goal

Eliminate the 8+ file, 5+ switch statement coordination required when adding new events by implementing an Event Plugin System where each event type is self-contained.

## Problem Statement

**Current Pain Points:**
- `Events.swift` (1,235 lines) contains `ParsedEvent` enum with 30 cases
- `ParsedEvent.parse()` has 40+ branch switch statement for decoding
- `ParsedEvent.sessionId` has another 30-branch switch for extraction
- `ChatViewModel.handleEvent()` has 30+ dispatch cases
- Adding ONE new event requires changes to 8+ files, 5+ locations

**Files touched per new event:**
1. Events.swift - Add struct + ParsedEvent case + parsing case
2. Events.swift - Add sessionId switch case
3. ChatViewModel+Events.swift - Add handler method
4. ChatViewModel.swift - Add dispatch case
5. ChatEventHandler.swift - Add Result struct + handler
6. Coordinator files (if complex)
7. Tests for all above

---

## Architecture Design

### Core Protocol: `EventPlugin`

```swift
/// Protocol for self-contained event types
protocol EventPlugin {
    /// Event type string (e.g., "agent.text_delta")
    static var eventType: String { get }

    /// The Decodable event struct type
    associatedtype EventData: Decodable

    /// Parse raw JSON data into typed event (default uses JSONDecoder)
    /// Override for custom parsing (e.g., ToolEndEvent)
    static func parse(from data: Data) throws -> EventData

    /// Extract sessionId for filtering
    static func sessionId(from event: EventData) -> String?

    /// Transform to UI-ready result (optional)
    static func transform(_ event: EventData) -> (any EventResult)?
}

/// Marker protocol for handler results
protocol EventResult {}

/// Default implementation
extension EventPlugin {
    static func parse(from data: Data) throws -> EventData {
        try JSONDecoder().decode(EventData.self, from: data)
    }
}
```

### Event Registry

```swift
/// Central registry for event plugins
final class EventRegistry {
    static let shared = EventRegistry()

    private var plugins: [String: any EventPluginBox] = [:]

    func register<P: EventPlugin>(_ plugin: P.Type) {
        plugins[P.eventType] = EventPluginBoxImpl<P>()
    }

    func parse(type: String, data: Data) -> ParsedEventV2? {
        guard let box = plugins[type] else {
            return .unknown(type)
        }
        return box.parse(data: data)
    }

    func registerAll() {
        register(TextDeltaPlugin.self)
        register(ThinkingDeltaPlugin.self)
        register(ToolStartPlugin.self)
        // ... all plugins
    }
}
```

### ParsedEventV2 (Parallel System During Migration)

```swift
/// New unified event wrapper for plugin system
enum ParsedEventV2 {
    case plugin(type: String, event: Any, sessionId: String?, transform: () -> (any EventResult)?)
    case unknown(String)
    case legacy(ParsedEvent)  // Fallback during migration

    var sessionId: String? { ... }
    func matchesSession(_ targetSessionId: String?) -> Bool { ... }
}
```

---

## File Organization

```
Sources/
  Core/
    Events/
      Plugins/
        EventPlugin.swift           # Protocol definition
        EventRegistry.swift         # Central registry
        ParsedEventV2.swift         # New enum wrapper

        Streaming/
          TextDeltaPlugin.swift
          ThinkingDeltaPlugin.swift
          TurnStartPlugin.swift
          TurnEndPlugin.swift

        Tool/
          ToolStartPlugin.swift
          ToolEndPlugin.swift

        Lifecycle/
          CompletePlugin.swift
          ErrorPlugin.swift
          CompactionPlugin.swift
          ContextClearedPlugin.swift
          MessageDeletedPlugin.swift
          SkillRemovedPlugin.swift

        Session/
          ConnectedPlugin.swift

        Subagent/
          SubagentSpawnedPlugin.swift
          SubagentStatusPlugin.swift
          SubagentCompletedPlugin.swift
          SubagentFailedPlugin.swift
          SubagentEventPlugin.swift

        PlanMode/
          PlanModeEnteredPlugin.swift
          PlanModeExitedPlugin.swift

        UICanvas/
          UIRenderStartPlugin.swift
          UIRenderChunkPlugin.swift
          UIRenderCompletePlugin.swift
          UIRenderErrorPlugin.swift
          UIRenderRetryPlugin.swift

        Browser/
          BrowserFramePlugin.swift
          BrowserClosedPlugin.swift

        Todo/
          TodosUpdatedPlugin.swift

Tests/
  Core/
    Events/
      Plugins/
        EventPluginProtocolTests.swift
        EventRegistryTests.swift
        EventPluginIntegrationTests.swift
        Streaming/
          TextDeltaPluginTests.swift
          ...
```

---

## Implementation Phases

### Phase 1: Core Infrastructure + First Plugin (TDD)

**Goal:** Establish foundation with zero risk to existing functionality.

**Step 1.1: Write Tests First**
```swift
// EventPluginProtocolTests.swift
func testAllPluginsConformToProtocol() { ... }
func testEventTypesAreUnique() { ... }

// EventRegistryTests.swift
func testParseKnownEventType() { ... }
func testParseUnknownEventType() { ... }
func testRegisteredPluginCount() { ... }

// TextDeltaPluginTests.swift
func testParseValidEvent() { ... }
func testParseWithoutOptionalFields() { ... }
func testSessionIdExtraction() { ... }
func testTransform() { ... }

// Integration tests
func testTextDeltaParityWithLegacy() { ... }
```

**Step 1.2: Implement Protocol & Registry**
- Create `EventPlugin` protocol
- Create `EventRegistry` singleton
- Create `ParsedEventV2` enum
- Implement type-erased storage

**Step 1.3: Implement TextDeltaPlugin**
- Reference implementation for simple events
- Full test coverage

**Step 1.4: Add Parallel Parsing to RPCClient**
```swift
private func handleEventData(_ data: Data) {
    // NEW: Try plugin system (feature flag)
    if FeatureFlags.useEventPlugins {
        if let eventV2 = EventRegistry.shared.parse(type: extractType(data), data: data) {
            _eventPublisherV2.send(eventV2)
        }
    }

    // EXISTING: Always run legacy during migration
    guard let event = ParsedEvent.parse(from: data) else { return }
    _eventPublisher.send(event)
}
```

**Step 1.5: Verify**
- All existing tests pass
- New plugin tests pass
- TextDelta parsed identically by both systems

### Phase 2: Migrate Simple Events

**Events (straightforward Decodable):**
- ThinkingDeltaPlugin
- TurnStartPlugin
- CompactionPlugin
- ContextClearedPlugin
- MessageDeletedPlugin
- SkillRemovedPlugin
- ConnectedPlugin

**Per-Event Checklist:**
- [ ] Create plugin file in category folder
- [ ] Define EventData struct (copy from Events.swift)
- [ ] Define Result struct
- [ ] Implement sessionId extraction
- [ ] Implement transform
- [ ] Write parsing tests (valid, missing fields, edge cases)
- [ ] Write transform tests
- [ ] Write parity test vs legacy
- [ ] Register in EventRegistry

### Phase 3: Migrate Complex Events

**Events (custom Decodable):**
- ToolEndPlugin - output as String OR ContentBlock array
- TurnEndPlugin - cost as Double OR String
- AgentTurnPlugin - nested content blocks with tool_use/tool_result

**Additional Testing:**
- Edge cases for type coercion
- Malformed JSON handling
- Partial data scenarios

### Phase 4: Complete Migration + Cleanup

**Migrate remaining:**
- Plan mode events
- UI canvas events
- Browser events
- Todo events
- Subagent events

**Update consumers:**
- RPCClient.eventPublisher type change
- ChatViewModel.handleEvent() switch update

**Remove legacy:**
- Delete ParsedEvent enum
- Delete EventType enum
- Clean up Events.swift

---

## Critical Files

| File | Purpose |
|------|---------|
| `Sources/Models/Events/Events.swift` | Current ParsedEvent + all structs (will be progressively deprecated) |
| `Sources/Services/Network/RPCClient.swift` | Entry point - `handleEventData()` where parallel parsing added |
| `Sources/ViewModels/Chat/ChatViewModel.swift` | `handleEvent()` dispatch (will support both systems) |
| `Sources/ViewModels/Handlers/ChatEventHandler.swift` | Pattern for Result structs |

---

## Test Contracts (TDD)

### 1. Protocol Conformance Tests
```swift
func testAllPluginsConformToProtocol()
func testEventTypesAreUnique()
func testAllPluginsHaveNonEmptyEventType()
```

### 2. Registry Tests
```swift
func testParseKnownEventType()
func testParseUnknownEventType()
func testRegisteredPluginCount()
func testSessionIdExtraction()
```

### 3. Plugin Tests (per plugin)
```swift
func testParseValidEvent()
func testParseWithoutOptionalFields()
func testParseMalformedJSON()
func testSessionIdExtraction()
func testSessionIdNilWhenMissing()
func testTransform()
```

### 4. Integration Tests
```swift
func testParityWithLegacySystem()  // For each migrated event
func testAllEventTypesParity()     // Bulk comparison
```

---

## Verification

**After each phase:**
```bash
# Build iOS app
xcodebuild -project packages/ios-app/TronMobile.xcodeproj \
  -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Run tests
xcodebuild -project packages/ios-app/TronMobile.xcodeproj \
  -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

**Parity verification:**
- Log both systems' output during migration
- Compare parsed sessionId, type, transform results
- Zero divergence before removing legacy

---

## Migration Safety

| Risk | Mitigation |
|------|------------|
| Breaking existing parsing | Parallel systems - both run during migration |
| Missing edge cases | Comprehensive parity tests |
| Custom Decodable bugs | Copy exact logic from existing structs |
| Circular imports | Keep plugins in separate folder tree |
| Performance regression | Benchmark parsing before/after |

---

## Success Criteria

**Phase 1:**
- [ ] EventPlugin protocol defined with tests
- [ ] EventRegistry implemented with tests
- [ ] TextDeltaPlugin migrated with parity verified
- [ ] Feature flag controls new system

**Phase 2:**
- [ ] 7 simple events migrated
- [ ] All parity tests pass
- [ ] No existing test failures

**Phase 3:**
- [ ] 3 complex events migrated (custom Decodable)
- [ ] Edge case coverage complete

**Phase 4:**
- [ ] All 30 events migrated
- [ ] Legacy ParsedEvent deleted
- [ ] Events.swift reduced to shared types only
- [ ] Adding new event = 1 file + register call

---

## Example: Adding New Event (After Migration)

**Before (8+ files):**
1. Add struct to Events.swift
2. Add case to ParsedEvent enum
3. Add case to parse() switch
4. Add case to sessionId switch
5. Add case to EventType enum
6. Add handler to ChatViewModel+Events
7. Add dispatch case to handleEvent()
8. Add tests

**After (1 file + 1 line):**
```swift
// 1. Create Sources/Core/Events/Plugins/MyCategory/NewEventPlugin.swift
enum NewEventPlugin: EventPlugin {
    static let eventType = "agent.new_event"

    struct EventData: Decodable {
        let type: String
        let sessionId: String?
        let data: DataPayload
        struct DataPayload: Decodable { ... }
    }

    struct Result: EventResult { ... }

    static func sessionId(from event: EventData) -> String? { event.sessionId }
    static func transform(_ event: EventData) -> (any EventResult)? { ... }
}

// 2. Add to EventRegistry.registerAll():
register(NewEventPlugin.self)
```

Done. One file, one registration line, fully self-contained.

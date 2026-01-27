# EventDatabase Refactoring Plan

## Status: ALL PHASES COMPLETE ✅

**Final Results:**
- EventDatabase.swift: 1,356 → 948 LOC (-408 LOC, -30.1%)
- DatabaseSchema.swift: 202 LOC (NEW - schema management)
- EventDeduplicator.swift: 119 LOC (NEW - business logic)
- EventTreeBuilder.swift: 67 LOC (NEW - presentation logic)
- ContentExtractor.swift: 118 → 177 LOC (+59 LOC, consolidated payload methods)
- All 27 EventDatabase tests pass
- Deprecated deleteLocalDuplicates removed
- columnExists moved to DatabaseSchema

---

## Goal
Break up the 1,356 LOC EventDatabase into modular, testable components with zero regressions.

---

## Current State

### File Structure (1,356 LOC)
```
EventDatabase.swift                    1,356 LOC  (single monolithic file)
├── Schema creation & migrations        ~150 LOC
├── Event CRUD operations               ~200 LOC
├── Session CRUD operations             ~150 LOC
├── Sync state operations                ~70 LOC
├── Thinking block extraction            ~50 LOC
├── Tree visualization building          ~50 LOC
├── Deduplication logic                 ~150 LOC
├── Fork/branch finding                  ~50 LOC
├── Local duplicate deletion            ~100 LOC
├── Private helpers                     ~100 LOC
└── Error types                          ~20 LOC
```

### Responsibilities (7+ distinct concerns)
1. **Schema Management** - Table creation, migrations, column checks
2. **Event CRUD** - Insert, get, delete events
3. **Session CRUD** - Insert, get, delete sessions
4. **Sync State** - Track sync cursors per session
5. **Tree Building** - Build visualization tree from events (PRESENTATION LOGIC)
6. **Deduplication** - Remove duplicate events with business rules (BUSINESS LOGIC)
7. **Content Analysis** - Extract text, check for tool blocks (DUPLICATED)
8. **Fork/Branch Finding** - Find sibling branches at fork points

### Method Count: 34 public methods

---

## Problems

### 1. Business Logic in Database Layer
The `deduplicateSession()` method (100+ LOC) contains complex business rules:
- Determines which events to keep based on content richness (tool blocks)
- Prefers server events (`evt_*`) over local events (UUIDs)
- Groups events by type and content prefix for matching

This logic belongs in a service layer, not the database.

### 2. Duplicated Code - hasToolBlocks & extractTextContent
These helper functions are defined as nested functions in TWO places:
- Inside `deduplicateSession()` (lines 996-1033)
- Inside `deleteLocalDuplicates()` (lines 492-530)

We already created `ContentExtractor` which does the same thing!

```swift
// DUPLICATED in EventDatabase.swift (appears TWICE):
func hasToolBlocks(_ payload: [String: AnyCodable]) -> Bool { ... }
func extractTextContent(_ payload: [String: AnyCodable]) -> String { ... }

// ALREADY EXISTS in ContentExtractor.swift:
static func extractToolCount(from content: Any?) -> Int
static func extractText(from content: Any?) -> String
```

### 3. Presentation Logic in Database
`buildTreeVisualization()` builds UI tree nodes in the database layer:
```swift
func buildTreeVisualization(_ sessionId: String) throws -> [EventTreeNode] {
    // Builds parent-child map
    // Creates EventTreeNode with: depth, isBranchPoint, isHead, childCount
    // This is PRESENTATION logic, not data access
}
```

### 4. Schema Migrations Inline
Schema creation and migrations are mixed into `createTables()`:
```swift
private func createTables() throws {
    // Create tables (50 LOC)
    // Migration: Add cost column (5 LOC)
    // Migration: Add is_fork column (5 LOC)
    // Migration: Add last_turn_input_tokens (5 LOC)
    // Migration: Add cache token columns (10 LOC)
    // Migration: Add server_origin (5 LOC)
    // Migration: Table rebuild for old schema (30 LOC)
    // Create indexes (10 LOC)
}
```

### 5. Deprecated Code Still Present
`deleteLocalDuplicates()` has `@deprecated` comment but is still 100+ LOC of code.

---

## Target Architecture

```
Database/
├── EventDatabase.swift              (~600 LOC - core CRUD only)
│
├── Schema/                          # NEW - extracted schema management
│   └── DatabaseSchema.swift         (~200 LOC) - table creation & migrations
│
├── Services/                        # Business logic (NOT in Database/)
│   └── EventDeduplicator.swift      (~100 LOC) - deduplication using ContentExtractor
│
└── Utilities/                       # Already exists
    └── ContentExtractor.swift       (existing - reuse for hasToolBlocks/extractText)

ViewModels/ or Services/
└── EventTreeBuilder.swift           (~80 LOC) - tree visualization from events
```

**Estimated: 1,356 → ~600 LOC in EventDatabase** (56% reduction)

---

## Implementation Phases

### Phase 1: Add Characterization Tests
**Goal**: Ensure coverage for business logic before extraction.

Current test coverage (23 tests):
- ✅ Event CRUD (insert, get, delete)
- ✅ Session CRUD (insert, get, delete)
- ✅ Ancestors/children traversal
- ✅ Tree visualization
- ✅ Sync state
- ❌ Deduplication logic (NOT TESTED)
- ❌ hasToolBlocks/extractTextContent (NOT TESTED)

**Add tests for**:
1. `deduplicateSession` - duplicate detection and removal
2. `hasToolBlocks` - tool block detection in various payload formats
3. Content extraction for deduplication matching

**Deliverables**:
- [x] Test coverage for deduplication logic (4 new tests)
- [x] Test coverage for content analysis helpers (8 new tests)
- [x] Baseline passing (27 total EventDatabase tests)

---

### Phase 2: Consolidate Content Analysis with ContentExtractor
**Goal**: Eliminate duplicated hasToolBlocks/extractTextContent.

**Current duplication**:
```swift
// In deduplicateSession() - nested function
func hasToolBlocks(_ payload: [String: AnyCodable]) -> Bool { ... }
func extractTextContent(_ payload: [String: AnyCodable]) -> String { ... }

// In deleteLocalDuplicates() - nested function (AGAIN!)
func hasToolBlocks(_ payload: [String: AnyCodable]) -> Bool { ... }
func extractTextContent(_ payload: [String: AnyCodable]) -> String { ... }
```

**Solution**: Extend existing `ContentExtractor` with payload-based methods:
```swift
extension ContentExtractor {
    /// Check if payload has tool_use or tool_result blocks
    static func hasToolBlocks(in payload: [String: AnyCodable]) -> Bool

    /// Extract text content from payload for duplicate matching
    static func extractTextForMatching(from payload: [String: AnyCodable]) -> String
}
```

**Files to modify**:
- Extend `Services/Utilities/ContentExtractor.swift`
- Update `EventDatabase.swift` to use ContentExtractor
- Remove nested function definitions (2 places)

**Deliverables**:
- [x] ContentExtractor extended with payload methods (hasToolBlocks, extractTextForMatching)
- [x] Duplicated nested functions removed from EventDatabase
- [x] Tests pass (8 new ContentExtractor tests)

---

### Phase 3: Extract EventDeduplicator
**Goal**: Move deduplication business logic out of database layer.

**Current** (in EventDatabase.swift, 150+ LOC):
```swift
func deduplicateSession(_ sessionId: String) throws -> Int {
    let events = try getEventsBySession(sessionId)
    // Complex grouping logic
    // Business rules for which events to keep
    // Deletion of duplicates
}

func deduplicateAllSessions() throws -> Int { ... }

// Also: deleteLocalDuplicates() - deprecated but still present
```

**Extract to**:
```swift
/// Handles event deduplication with business rules
/// - Prefers events with tool blocks (richer content)
/// - Prefers server events (evt_*) over local events (UUIDs)
final class EventDeduplicator {
    private let eventDB: EventDatabase

    init(eventDB: EventDatabase)

    /// Deduplicate events for a session
    /// Returns the number of duplicates removed
    func deduplicateSession(_ sessionId: String) throws -> Int

    /// Deduplicate all sessions
    func deduplicateAllSessions() throws -> Int

    /// Find duplicate event IDs to remove (for testing/preview)
    func findDuplicates(in events: [SessionEvent]) -> [String]
}
```

**Files to modify**:
- Create `Services/EventDeduplicator.swift`
- Update `EventDatabase.swift` - remove deduplication methods
- Update callers (EventStoreManager+Operations.swift)
- Delete `deleteLocalDuplicates()` (deprecated)

**Deliverables**:
- [x] `EventDeduplicator.swift` created (119 LOC)
- [x] Deduplication logic removed from EventDatabase (delegated to EventDeduplicator)
- [x] Deprecated `deleteLocalDuplicates` removed
- [x] Tests pass (all 27 EventDatabase tests)

---

### Phase 4: Extract EventTreeBuilder
**Goal**: Move presentation logic out of database layer.

**Current** (in EventDatabase.swift, ~50 LOC):
```swift
func buildTreeVisualization(_ sessionId: String) throws -> [EventTreeNode] {
    let events = try getEventsBySession(sessionId)
    // Build parent-child map
    // Recursive node building with depth, isBranchPoint, isHead
}
```

**Extract to**:
```swift
/// Builds tree visualization from session events
enum EventTreeBuilder {
    /// Build tree nodes from events
    static func buildTree(
        from events: [SessionEvent],
        headEventId: String?
    ) -> [EventTreeNode]

    /// Build parent-child relationship map
    static func buildChildrenMap(
        from events: [SessionEvent]
    ) -> [String?: [SessionEvent]]
}
```

**Files to modify**:
- Create `Services/Utilities/EventTreeBuilder.swift`
- Update `EventDatabase.swift` - delegate to EventTreeBuilder
- Keep `buildTreeVisualization` as thin wrapper for compatibility

**Deliverables**:
- [x] `EventTreeBuilder.swift` created (67 LOC)
- [x] Tree building logic extracted
- [x] EventDatabase delegates to builder (thin wrapper)
- [x] Tests pass (testBuildTreeVisualization, testBranchPointDetection)

---

### Phase 5: Extract DatabaseSchema
**Goal**: Separate schema management from CRUD operations.

**Current** (in EventDatabase.swift, ~200 LOC):
```swift
private func createTables() throws {
    // Events table creation
    // Events indexes
    // Sessions table creation
    // 6+ migrations for existing databases
    // Sessions indexes
    // Sync state table
}

private func columnExists(table: String, column: String) throws -> Bool
```

**Extract to**:
```swift
/// Manages database schema creation and migrations
enum DatabaseSchema {
    /// Current schema version
    static let version = 7

    /// Create all tables and indexes
    static func createTables(db: OpaquePointer?) throws

    /// Run any needed migrations
    static func migrate(db: OpaquePointer?) throws

    /// Check if a column exists
    static func columnExists(
        table: String,
        column: String,
        db: OpaquePointer?
    ) throws -> Bool
}
```

**Files to modify**:
- Create `Database/Schema/DatabaseSchema.swift`
- Update `EventDatabase.swift` - delegate to DatabaseSchema
- Remove inline schema code from EventDatabase

**Deliverables**:
- [x] `DatabaseSchema.swift` created (202 LOC)
- [x] Schema logic separated from CRUD (createTables, migrations, columnExists)
- [x] Migrations versioned and organized (addColumnIfNotExists helper)
- [x] Tests pass (27 EventDatabase tests)

---

### Phase 6: Simplify EventDatabase Core
**Goal**: EventDatabase becomes pure CRUD + query operations.

After phases 2-5, EventDatabase should contain only:
- Initialization (open, close)
- Event CRUD (insert, get, delete)
- Session CRUD (insert, get, delete)
- Sync state CRUD (get, update)
- Query operations (getAncestors, getChildren, getForkedSessions)
- Thin delegation methods (buildTreeVisualization -> EventTreeBuilder)

**Remaining methods (~25, down from 34)**:
```swift
// Lifecycle
init(), initialize(), close()

// Event CRUD
insertEvent(), insertEvents(), insertEventsIgnoringDuplicates()
getEvent(), getEventsBySession(), deleteEventsBySession()
getAncestors(), getChildren(), eventExists()

// Session CRUD
insertSession(), getSession(), getAllSessions(), deleteSession()
getSessionsByOrigin(), getSessionOrigin(), sessionExists()

// Fork queries
getForkedSessions(), getSiblingBranches()

// Sync state
getSyncState(), updateSyncState()

// Thinking (could be extracted later)
getThinkingEvents(), getThinkingContent()

// Utilities
clearAll()

// Delegation
buildTreeVisualization() -> EventTreeBuilder
```

**Deliverables**:
- [x] EventDatabase reduced to 948 LOC (from 1,356 - 30% reduction)
- [x] Single responsibility: data access (CRUD + queries)
- [x] No business logic (deduplication extracted to EventDeduplicator)
- [x] No presentation logic (tree building extracted to EventTreeBuilder)
- [x] No schema management (extracted to DatabaseSchema)
- [x] Tests pass (27 EventDatabase tests)

---

### Phase 7: Cleanup & Documentation
**Goal**: Final polish.

1. Add documentation to new components
2. Update any callers that used deprecated methods
3. Verify EventStoreManager works correctly with new structure
4. Run full test suite
5. Manual smoke test on device

**Deliverables**:
- [x] Documentation complete (all new files have doc comments)
- [x] All tests pass (27 EventDatabase tests)
- [x] Protocol sync verified (EventDatabaseProtocol updated with missing methods)

---

## Files to Create

| File | LOC | Purpose |
|------|-----|---------|
| `Database/Schema/DatabaseSchema.swift` | ~200 | Schema creation & migrations |
| `Services/EventDeduplicator.swift` | ~100 | Deduplication business logic |
| `Services/Utilities/EventTreeBuilder.swift` | ~80 | Tree visualization building |

**Total new: ~380 LOC**

## Files to Modify

| File | Before | After | Change |
|------|--------|-------|--------|
| `EventDatabase.swift` | 1,356 | ~600 | -756 LOC |
| `ContentExtractor.swift` | 118 | ~150 | +32 LOC (payload methods) |
| `EventStoreManager+Operations.swift` | 333 | ~340 | +7 LOC (use EventDeduplicator) |

**Net change**: 1,356 → ~600 LOC in EventDatabase (56% reduction)

---

## Verification

### After Each Phase
```bash
xcodebuild -scheme TronMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild test -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TronMobileTests
```

### Critical Tests
- Event CRUD (insert, get, delete)
- Session CRUD (insert, get, delete)
- Ancestor/child traversal
- Tree visualization
- Deduplication (NEW tests)
- Content extraction (NEW tests)

### Manual Testing
1. Open dashboard - verify sessions load
2. Enter a session - verify events load correctly
3. Fork a session - verify tree visualization works
4. Run repair/deduplication - verify duplicates removed
5. Switch server environments - verify origin filtering works

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaking deduplication | Add characterization tests first |
| Tree visualization regression | Keep thin wrapper in EventDatabase for compatibility |
| Schema migration issues | Test with existing databases before/after |
| Performance regression | Keep SQLite operations in EventDatabase, only extract logic |

---

## Dependencies

- **ContentExtractor**: Already exists, extend with payload methods
- **EventDeduplicator**: Depends on EventDatabase (for queries) and ContentExtractor
- **EventTreeBuilder**: No dependencies, pure function
- **DatabaseSchema**: No dependencies, static methods

**Recommended order**: ContentExtractor → EventDeduplicator → EventTreeBuilder → DatabaseSchema → Core cleanup

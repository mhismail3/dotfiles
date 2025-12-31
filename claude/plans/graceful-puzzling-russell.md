# Comprehensive Test Suite Plan for Claude Code CLI Parity

## Executive Summary

**Goal**: Achieve 100% feature parity with Claude Code CLI through a robust, test-driven test suite
**Current State**: 72 unit tests, 0 integration tests, 0 frontend tests, 0 E2E tests
**Target State**: 350+ tests across all layers with automated parity verification

---

## Test Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         E2E Tests (Playwright)                   │
│         Session flows, Feature parity, Visual regression         │
├─────────────────────────────────────────────────────────────────┤
│                    Integration Tests (Docker)                     │
│      Hook→WS pipeline, Session persistence, Protocol tests       │
├──────────────────────┬──────────────────────────────────────────┤
│   Backend Unit Tests │         Frontend Unit Tests               │
│   (Rust + proptest)  │    (Vitest + SolidJS Testing Library)    │
├──────────────────────┴──────────────────────────────────────────┤
│                      Mock Infrastructure                          │
│   Mock Claude CLI, Mock WebSocket, Fixtures from real sessions   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Foundation (Days 1-2)

### 1.1 Backend Test Dependencies

**File: `Cargo.toml` (workspace)**
```toml
[workspace.dependencies]
proptest = "1.4"
tokio-test = "0.4"
tower = { version = "0.5", features = ["util"] }
axum-test = "0.3"
tempfile = "3.15"
```

### 1.2 Frontend Test Stack

**File: `frontend/package.json` additions**
```json
{
  "devDependencies": {
    "vitest": "^2.1.0",
    "@vitest/coverage-v8": "^2.1.0",
    "@solidjs/testing-library": "^0.8.10",
    "@testing-library/jest-dom": "^6.6.0",
    "jsdom": "^25.0.0",
    "mock-socket": "^9.3.1",
    "@playwright/test": "^1.48.0"
  },
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "test:e2e": "playwright test"
  }
}
```

### 1.3 Directory Structure

```
clauset/
├── tests/                              # Workspace integration tests
│   ├── fixtures/
│   │   └── hook_events/                # Real JSON from Claude Code
│   │       ├── session_start.json
│   │       ├── user_prompt_submit.json
│   │       ├── pre_tool_use_*.json
│   │       ├── post_tool_use_*.json
│   │       ├── stop.json
│   │       └── ... (12 event types)
│   ├── common/mod.rs                   # Test utilities
│   ├── e2e_hook_pipeline.rs
│   └── session_persistence.rs
├── crates/
│   ├── clauset-types/tests/
│   ├── clauset-core/tests/
│   └── clauset-server/tests/
└── frontend/
    ├── src/test/
    │   ├── setup.ts
    │   └── mocks/
    ├── vitest.config.ts
    ├── playwright.config.ts
    └── e2e/
```

### 1.4 Fixture Collection

Capture real hook events from Claude Code sessions:
1. Enable debug logging in hook script
2. Run sessions covering all 12 hook event types
3. Sanitize and store as JSON fixtures

**12 Required Fixtures:**
- SessionStart, SessionEnd
- UserPromptSubmit
- PreToolUse (Read, Bash, Write, Edit, etc.)
- PostToolUse, PostToolUseFailure
- Stop
- SubagentStart, SubagentStop
- PreCompact, PermissionRequest, Notification

---

## Phase 2: Backend Unit Tests (Days 3-5)

### 2.1 Hook Event Parsing (P0 - Critical)

**File: `crates/clauset-server/tests/hooks_tests.rs`**
**Target: 40+ tests**

| Test Category | Count | Focus |
|---------------|-------|-------|
| Event parsing | 12 | One test per hook event type |
| Context window | 5 | Token extraction, cache tokens |
| AskUserQuestion | 5 | Question batching, option indices |
| Infrastructure filtering | 5 | Hook script detection |
| Error handling | 5 | Malformed payloads |
| Broadcasting | 8 | ProcessEvent emission |

Key tests:
```rust
test_parse_all_12_event_types_from_fixtures()
test_context_window_calculates_percent_correctly()
test_ask_user_question_batches_into_single_prompt()
test_bash_hook_infrastructure_filtered_out()
test_malformed_payload_returns_400()
```

### 2.2 WebSocket Message Protocol (P0 - Critical)

**File: `crates/clauset-types/src/ws.rs` (add tests)**
**Target: 25+ tests**

| Test Category | Count | Focus |
|---------------|-------|-------|
| Serialization | 15 | All WsServerMessage variants |
| Parsing | 8 | WsClientMessage variants |
| Property tests | 2 | Roundtrip serialization |

Key tests:
```rust
test_all_variants_have_snake_case_type_tag()
test_chat_event_struct_variant_avoids_serde_conflict()
test_terminal_chunk_preserves_binary_data()
proptest!(test_ws_message_roundtrip)
```

### 2.3 Session Lifecycle (P1 - High)

**File: `crates/clauset-core/tests/session_lifecycle_tests.rs`**
**Target: 20+ tests**

Key tests:
```rust
test_create_sets_status_created()
test_start_transitions_to_active()
test_terminate_persists_activity_before_stop()
test_resume_requires_valid_claude_session_id()
test_resume_with_nil_id_returns_not_resumable()
test_terminal_buffer_persisted_and_restored()
```

### 2.4 Terminal Buffer (P0 - Critical)

**File: `crates/clauset-core/src/buffer.rs` (extend existing)**
**Target: 40+ tests (currently 24)**

Add property-based tests:
```rust
proptest! {
    test_sequence_always_monotonic(chunks)
    test_buffer_never_exceeds_max_size(chunks)
    test_eviction_preserves_recent_chunks()
}

test_hook_context_received_disables_regex_parsing()
test_gap_detection_with_missing_sequence()
```

### 2.5 Chat Processor (P1 - High)

**File: `crates/clauset-core/tests/chat_processor_tests.rs`**
**Target: 20+ tests**

Key tests:
```rust
test_user_prompt_creates_user_and_assistant_messages()
test_pre_tool_use_adds_tool_call()
test_post_tool_use_completes_tool_call()
test_stop_reads_transcript_and_populates_content()
test_transcript_jsonl_nested_format_parsed()
```

### 2.6 Interactive Prompts (P1 - High)

**File: `crates/clauset-types/src/interactive.rs` (add tests)**
**Target: 10+ tests**

Key tests:
```rust
test_option_indices_are_one_based()
test_multi_question_batched_correctly()
test_interactive_event_serialization()
```

---

## Phase 3: Frontend Unit Tests (Days 6-8)

### 3.1 Vitest Configuration

**File: `frontend/vitest.config.ts`**
```typescript
export default defineConfig({
  plugins: [solid()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    coverage: {
      thresholds: { lines: 60, branches: 50, functions: 55 }
    }
  }
});
```

### 3.2 Store Tests (P0 - Critical)

| Store | File | Tests | Focus |
|-------|------|-------|-------|
| messages | `stores/__tests__/messages.test.ts` | 20+ | CRUD, localStorage, ChatEvent handling |
| terminal | `stores/__tests__/terminal.test.ts` | 10+ | Base64 encoding, storage limits |
| interactive | `stores/__tests__/interactive.test.ts` | 15+ | Carousel state, answer sequencing |
| commands | `stores/__tests__/commands.test.ts` | 8+ | Filtering, caching |

### 3.3 WebSocket Manager Tests (P0 - Critical)

**File: `lib/__tests__/ws.test.ts`**
**Target: 25+ tests**

Using `mock-socket` for WebSocket simulation:
```typescript
test_connection_state_machine()
test_sync_request_sent_on_connect()
test_sequence_tracking_for_in_order_chunks()
test_out_of_order_chunks_buffered()
test_gap_recovery_after_500ms()
test_ack_batching_at_100ms_intervals()
test_dimension_updates_stop_after_initial_sync()
```

### 3.4 Component Tests (P2 - Medium)

**File: `components/chat/__tests__/MessageBubble.test.tsx`**
```typescript
test_user_message_styling()
test_thinking_indicator_when_streaming_empty()
test_markdown_rendering()
test_system_messages_with_correct_colors()
test_tool_calls_expandable()
test_mcp_tool_parsing_and_purple_accent()
test_todowrite_status_icons()
```

**File: `components/commands/__tests__/CommandPicker.test.tsx`**
```typescript
test_filters_commands_by_query()
test_groups_by_category()
test_keyboard_navigation()
test_selects_on_enter()
```

---

## Phase 4: Integration Tests (Days 9-11)

### 4.1 Test Infrastructure

**File: `tests/common/mod.rs`**
```rust
pub struct TestContext {
    pub temp_dir: TempDir,
    pub session_manager: SessionManager,
    pub event_rx: broadcast::Receiver<ProcessEvent>,
}

pub fn load_hook_fixture(name: &str) -> HookEventPayload { ... }
pub fn create_test_app() -> (Router, Arc<AppState>) { ... }
```

### 4.2 Hook → WebSocket Pipeline Test

**File: `tests/e2e_hook_pipeline.rs`**
```rust
#[tokio::test]
async fn test_hook_to_websocket_pipeline() {
    // 1. Create test app with mock session
    // 2. Connect WebSocket test client
    // 3. Send hook events from fixtures
    // 4. Verify WebSocket receives expected messages
    // 5. Check message types and content match
}
```

### 4.3 Session Persistence Test

**File: `tests/session_persistence.rs`**
```rust
#[tokio::test]
async fn test_session_survives_restart() {
    // Phase 1: Create session, add activity, persist
    // Phase 2: Recreate SessionManager, verify data restored
}
```

### 4.4 WebSocket Protocol Tests

```rust
test_sync_protocol_handshake()
test_sequence_monotonicity_under_load()
test_gap_recovery_under_packet_loss()
test_interactive_choice_sends_pty_navigation()
```

---

## Phase 5: E2E Tests with Playwright (Days 12-14)

### 5.1 Playwright Configuration

**File: `frontend/playwright.config.ts`**
```typescript
export default defineConfig({
  testDir: './e2e',
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'Mobile Safari', use: { ...devices['iPhone 14'] } }
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173'
  }
});
```

### 5.2 Feature Parity Tests (P0 - Critical)

**File: `frontend/e2e/feature-parity.spec.ts`**

| Feature | Test | Acceptance Criteria |
|---------|------|---------------------|
| TodoWrite | `test_todowrite_status_icons` | ○ pending, ◐ in_progress, ✓ completed |
| MCP Tools | `test_mcp_tool_parsing` | Server name extracted, purple accent |
| Subagent | `test_subagent_tracking` | Blue started pill, green stopped |
| Context Compaction | `test_context_compaction_notice` | Yellow notification, trigger shown |
| Permission Request | `test_permission_request` | Purple with lock icon |
| Tool Error | `test_tool_error_timeout` | Red with warning, timeout flag |
| Token Tracking | `test_accurate_token_counts` | Values from hook context_window |

### 5.3 Interactive Prompt Tests

**File: `frontend/e2e/interactive-prompt.spec.ts`**
```typescript
test_carousel_navigation_with_dots()
test_arrow_key_navigation()
test_multi_select_with_next_button()
test_send_all_responses_sequentially()
```

### 5.4 Terminal Reliability Tests

**File: `frontend/e2e/terminal-reliability.spec.ts`**
```typescript
test_sync_handshake_on_connect()
test_scroll_preserved_during_keyboard()
test_reconnection_recovers_buffer()
```

---

## Phase 6: CI/CD Integration (Day 15)

### 6.1 GitHub Actions Workflow

**File: `.github/workflows/test.yml`**
```yaml
name: Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Rust tests
        run: cargo test --workspace
      - name: Frontend tests
        run: cd frontend && npm test

  integration-tests:
    needs: unit-tests
    runs-on: ubuntu-latest
    steps:
      - name: Run integration tests
        run: cargo test --test '*'

  e2e-tests:
    needs: integration-tests
    runs-on: ubuntu-latest
    steps:
      - name: Install Playwright
        run: npx playwright install chromium
      - name: Run E2E tests
        run: cd frontend && npm run test:e2e
      - name: Upload report
        uses: actions/upload-artifact@v3
        with:
          name: playwright-report
          path: playwright-report/
```

---

## Coverage Targets

| Layer | Current | Target | Priority |
|-------|---------|--------|----------|
| Backend Unit | 72 tests | 155+ | P0 |
| Frontend Unit | 0 tests | 80+ | P0 |
| Integration | 0 tests | 30+ | P1 |
| E2E | 0 tests | 25+ | P1 |
| **Total** | **72** | **290+** | |

### Per-Module Targets

| Module | Current | Target |
|--------|---------|--------|
| `hooks.rs` | 0 | 40+ |
| `ws.rs` | 2 | 25+ |
| `buffer.rs` | 24 | 40+ |
| `session.rs` | 0 | 20+ |
| `chat_processor.rs` | 4 | 20+ |
| `interactive.rs` | 0 | 10+ |
| Frontend stores | 0 | 50+ |
| Frontend components | 0 | 30+ |

---

## Critical Files to Modify

### Backend
1. `crates/clauset-server/tests/hooks_tests.rs` (create)
2. `crates/clauset-types/src/ws.rs` (add tests)
3. `crates/clauset-core/tests/session_lifecycle_tests.rs` (create)
4. `crates/clauset-core/src/buffer.rs` (add property tests)
5. `crates/clauset-types/src/interactive.rs` (add tests)
6. `tests/common/mod.rs` (create test utilities)
7. `tests/fixtures/hook_events/*.json` (create from captures)

### Frontend
1. `frontend/package.json` (add test deps)
2. `frontend/vitest.config.ts` (create)
3. `frontend/src/test/setup.ts` (create)
4. `frontend/src/test/mocks/ws.ts` (create)
5. `frontend/src/stores/__tests__/*.test.ts` (create)
6. `frontend/src/lib/__tests__/ws.test.ts` (create)
7. `frontend/playwright.config.ts` (create)
8. `frontend/e2e/*.spec.ts` (create)

---

## Success Criteria

1. **All 12 hook event types** have parsing tests with real fixtures
2. **WebSocket protocol** tested for reliable streaming (sequence, gaps, ACKs)
3. **Session lifecycle** tested including resume with persistence
4. **Frontend stores** have 80%+ coverage on critical paths
5. **Feature parity tests** verify all CLI features work in chat mode
6. **CI passes** on every PR with test reports
7. **Zero flaky tests** through deterministic execution

---

## Implementation Order

1. **Week 1**: Foundation + Backend P0 tests (hooks, ws, buffer)
2. **Week 2**: Frontend setup + Store tests + WebSocket manager tests
3. **Week 3**: Integration tests + E2E setup + Feature parity tests
4. **Week 4**: CI integration + Coverage enforcement + Documentation

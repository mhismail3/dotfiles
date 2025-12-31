# Production-Grade Terminal Streaming Overhaul

## Problem Statement

Terminal streaming from backend to frontend fails under poor network conditions (5G vs WiFi):
1. **Blank terminal screen** - No output rendered when connection is slow
2. **Incorrect terminal width** - Terminal narrower than screen width on reconnection
3. **Silent message loss** - No delivery guarantees, no sequence numbers, no ACKs
4. **No gap recovery** - Reconnection doesn't recover missed messages

## Solution Overview

A complete overhaul of the backend-to-frontend terminal streaming system with:
- Reliable message delivery with sequence numbers and ACKs
- Robust connection state management with stale detection
- Font-resilient terminal sizing with server validation
- iOS-specific optimizations for PWA lifecycle

## Implementation Phases

---

## Phase 1: Reliable Streaming Protocol

**Goal**: Zero message loss with ordered delivery and gap recovery.

### 1.1 Backend: Sequenced Message Types

**File**: `crates/clauset-types/src/ws.rs`

Add new message types:
```rust
// Client → Server
SyncRequest { last_seq: u64, cols: u16, rows: u16 }
Ack { ack_seq: u64 }
RangeRequest { start_seq: u64, end_seq: u64 }

// Server → Client
TerminalChunk { seq: u64, data: Vec<u8>, timestamp: u64 }
SyncResponse { buffer_start_seq: u64, buffer_end_seq: u64, cols: u16, rows: u16, full_buffer: Option<Vec<u8>>, full_buffer_start_seq: Option<u64> }
ChunkBatch { start_seq: u64, data: Vec<u8>, chunk_count: u32, is_complete: bool }
BufferOverflow { new_start_seq: u64, requires_resync: bool }
```

### 1.2 Backend: Sequenced Ring Buffer

**File**: `crates/clauset-core/src/buffer.rs`

Replace `TerminalBuffer` with `SequencedRingBuffer`:
```rust
pub struct SequencedRingBuffer {
    chunks: VecDeque<SequencedChunk>,
    start_seq: u64,
    next_seq: u64,
    total_bytes: usize,
    max_bytes: usize,  // 500KB
}

pub struct SequencedChunk {
    seq: u64,
    data: Vec<u8>,
    timestamp: u64,
}
```

Key methods:
- `push(data) -> (seq, evicted_count)` - Assign sequence, evict old if needed
- `get_range(start, end) -> Vec<SequencedChunk>` - For gap recovery
- `get_all() -> (start_seq, data)` - For full buffer replay

### 1.3 Backend: Per-Client Stream State

**File**: `crates/clauset-server/src/websocket.rs`

Add client tracking:
```rust
struct ClientStreamState {
    ack_seq: u64,
    sent_seq: u64,
    pending_count: u32,
    last_ack_time: Instant,
}
```

Implement:
- `on_pty_output()` - Assign seq, broadcast `TerminalChunk`
- `on_client_ack()` - Update client state, send throttled chunks
- `on_sync_request()` - Handle reconnection with gap detection
- `on_range_request()` - Send missing chunks in batches

Flow control: Stop sending if `pending_count > 100`, resume on ACK.

### 1.4 Frontend: Sequence Tracking

**File**: `frontend/src/lib/ws.ts`

Add sequence tracking to WebSocket manager:
```typescript
interface StreamState {
  lastReceivedSeq: number;
  lastContiguousSeq: number;
  pendingChunks: Map<number, Uint8Array>;
  lastAckedSeq: number;
  ackTimer: number | null;
}
```

Implement:
- `onTerminalChunk()` - Process in-order or buffer out-of-order
- `scheduleAck()` - Batch ACKs (every 100ms or 10 chunks)
- `scheduleGapRecovery()` - Request missing range after 500ms timeout
- `onReconnect()` - Send `SyncRequest` with last known seq

### 1.5 Frontend: Update Message Handling

**File**: `frontend/src/pages/Session.tsx`

Update handlers for new message types:
- Handle `terminal_chunk` instead of `terminal_output`
- Handle `sync_response` for reconnection state
- Handle `chunk_batch` for gap recovery
- Handle `buffer_overflow` for forced resync

### 1.6 Integration Tests

**New File**: `crates/clauset-server/tests/streaming_reliability.rs`

Tests:
- Sequential delivery under normal conditions
- Gap detection and recovery
- Reconnection with partial catch-up
- Reconnection with full buffer (too far behind)
- Flow control under slow client

---

## Phase 2: Connection State Management

**Goal**: Clear connection states, stale detection, and iOS resilience.

### 2.1 Extended Connection States

**File**: `frontend/src/lib/ws.ts`

Extend states:
```typescript
type ConnectionState =
  | 'initial'      // Never connected
  | 'connecting'   // Active attempt
  | 'connected'    // Healthy (recent pong)
  | 'stale'        // Connected but no pong in 25s
  | 'reconnecting' // Triggered reconnect
  | 'backoff'      // Waiting before retry
  | 'failed'       // Max retries exceeded
  | 'suspended';   // iOS background
```

### 2.2 Heartbeat & Stale Detection

**File**: `frontend/src/lib/ws.ts`

Add heartbeat:
```typescript
const PING_INTERVAL_MS = 15000;
const PONG_TIMEOUT_MS = 5000;
const STALE_THRESHOLD_MS = 25000;
```

Logic:
- Send `Ping` every 15s when connected
- Expect `Pong` within 5s
- Mark `stale` if no pong in 25s
- Force reconnect after 2 missed pongs

### 2.3 Persistent Message Queue

**New File**: `frontend/src/lib/messageQueue.ts`

```typescript
class PersistentMessageQueue {
  enqueue(sessionId, type, payload): string;
  getForSession(sessionId): QueuedMessage[];
  markSent(id): void;
  persistToStorage(): void;
  loadFromStorage(): void;
}
```

- Max 200 messages, max 5 min age
- Persist to localStorage on visibility change
- Flush on reconnect

### 2.4 iOS PWA Lifecycle

**New File**: `frontend/src/lib/iosPwaLifecycle.ts`

Handle iOS-specific events:
- `visibilitychange` - Persist state when hidden
- `freeze/resume` - iOS 13+ page lifecycle
- `online/offline` - Network transitions
- `navigator.connection.change` - WiFi↔cellular switch

### 2.5 Connection Status UI

**File**: `frontend/src/components/ui/ConnectionStatus.tsx`

Enhanced banner with states:
- Connecting: spinner + attempt count
- Stale: yellow warning
- Reconnecting: spinner + countdown
- Failed: red + retry button
- Queue indicator: badge showing queued message count

### 2.6 Integration Tests

**New File**: `frontend/src/lib/__tests__/connectionState.test.ts`

Tests:
- State transitions
- Heartbeat timeout detection
- Queue persistence across page reload
- iOS visibility handling

---

## Phase 3: Robust Terminal Sizing

**Goal**: Correct dimensions always, even with slow font loading.

### 3.1 Font Loading Strategy

**New File**: `frontend/src/lib/fonts.ts`

```typescript
async function loadTerminalFont(options: {
  timeout: number;
  fontSize: number;
}): Promise<FontLoadResult> {
  // Stage 1: Try loading JetBrains Mono (2s timeout)
  // Stage 2: Fall back to system monospace
  // Stage 3: Measure character dimensions
  return { loaded, fontFamily, charWidth, charHeight, fallbackUsed };
}
```

### 3.2 Multi-Stage Dimension Calculation

**New File**: `frontend/src/lib/terminalSizing.ts`

```typescript
function calculateDimensions(fitAddon, context): TerminalDimensions {
  // Priority:
  // 1. FitAddon if font loaded correctly
  // 2. Container measurement with known char dimensions
  // 3. Container estimation with defaults
  // 4. Device-specific safe defaults
}
```

Returns confidence level: `'high' | 'medium' | 'low'`

### 3.3 Server-Side Validation

**New File**: `crates/clauset-core/src/sizing.rs`

```rust
fn validate_dimensions(cols, rows, device_hint) -> Result<ValidatedDimensions, DimensionError> {
  // Reject if:
  // - cols < 20 or > 300
  // - rows < 5 or > 100
  // - aspect ratio implausible (< 0.3 or > 8.0)
  // Warn if iPhone requesting > 60 cols
}
```

### 3.4 Dimension Negotiation Protocol

**File**: `crates/clauset-types/src/ws.rs`

Add negotiation messages:
```rust
// Client → Server
NegotiateDimensions { cols, rows, confidence, source, cell_width, font_loaded, device_hint }

// Server → Client
DimensionsConfirmed { cols, rows, adjusted, adjustment_reason }
DimensionsRejected { reason, suggested_cols, suggested_rows }
```

### 3.5 Update TerminalView Component

**File**: `frontend/src/components/terminal/TerminalView.tsx`

Refactor initialization:
1. Mount terminal immediately (skeleton)
2. Load fonts asynchronously (2s timeout)
3. Calculate dimensions with multi-stage strategy
4. Send `NegotiateDimensions` to server
5. Wait for `DimensionsConfirmed` before requesting buffer
6. Monitor for dimension mismatch in output

### 3.6 Integration Tests

**New File**: `frontend/src/lib/__tests__/terminalSizing.test.ts`

Tests:
- Font load timeout handling
- Fallback font dimension calculation
- Server dimension validation
- Dimension negotiation flow
- Mismatch detection and recovery

---

## Phase 4: Polish & iOS Optimizations

**Goal**: Production-ready with iOS-specific tuning.

### 4.1 Progressive Loading UI

**File**: `frontend/src/pages/Session.tsx`

Loading phases:
1. `connecting` - Skeleton terminal with spinner
2. `authenticating` - Waiting for SessionInit
3. `syncing` - Progress bar during buffer fetch
4. `rendering` - Writing buffer to terminal
5. `live` - Fully operational

### 4.2 Safari WebSocket Workarounds

**File**: `frontend/src/lib/ws.ts`

Safari-specific handling:
- Check message recency (45s threshold) even when `readyState === OPEN`
- Force reconnect on network type change
- Handle bfcache restoration

### 4.3 Tab Coordination

**File**: `frontend/src/lib/ws.ts`

Use `BroadcastChannel` to prevent duplicate connections:
- Announce connection on open
- Close if another tab takes over
- Single active connection per session

### 4.4 Error Recovery

**File**: `frontend/src/pages/Session.tsx`

Implement:
- Dimension mismatch auto-recovery
- Buffer corruption detection (invalid ANSI sequences)
- Automatic terminal clear + resync on corruption

### 4.5 E2E Tests

**New Files**: `e2e/terminal-*.spec.ts`

Playwright tests:
- iPhone viewport sizing
- Network throttling simulation
- Reconnection recovery
- Background/foreground transitions

---

## Files to Modify

### Backend (Rust)

| File | Changes |
|------|---------|
| `crates/clauset-types/src/ws.rs` | New message types (TerminalChunk, Ack, SyncRequest, etc.) |
| `crates/clauset-core/src/buffer.rs` | Replace with SequencedRingBuffer |
| `crates/clauset-core/src/sizing.rs` | **NEW** - Dimension validation |
| `crates/clauset-server/src/websocket.rs` | Per-client state, protocol handlers |
| `crates/clauset-server/tests/streaming_reliability.rs` | **NEW** - Integration tests |

### Frontend (SolidJS)

| File | Changes |
|------|---------|
| `frontend/src/lib/ws.ts` | Sequence tracking, heartbeat, extended states |
| `frontend/src/lib/fonts.ts` | **NEW** - Font loading with timeout |
| `frontend/src/lib/terminalSizing.ts` | **NEW** - Multi-stage dimension calc |
| `frontend/src/lib/messageQueue.ts` | **NEW** - Persistent message queue |
| `frontend/src/lib/iosPwaLifecycle.ts` | **NEW** - iOS lifecycle handlers |
| `frontend/src/pages/Session.tsx` | New message handling, loading phases |
| `frontend/src/components/terminal/TerminalView.tsx` | Font loading, dimension negotiation |
| `frontend/src/components/ui/ConnectionStatus.tsx` | Enhanced state display |
| `frontend/src/stores/terminal.ts` | Update for sequence tracking |

---

## Migration Notes

**Clean break** - No backward compatibility:
1. Deploy backend changes
2. Deploy frontend changes
3. Coordinated release (both at once)

Old `TerminalOutput` and `TerminalBuffer` messages will be removed.
New protocol is mandatory for all clients.

---

## Success Criteria

- [ ] No blank terminal on 5G connection
- [ ] Correct terminal width on all reconnections
- [ ] Zero message loss (verified by sequence numbers)
- [ ] Gap recovery within 500ms
- [ ] Stale connection detected within 25s
- [ ] iOS background/foreground handled gracefully
- [ ] All integration tests passing

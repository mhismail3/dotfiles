# iOS App Enhanced Reconnection System

## Problem Statement
Building on the previous reconnection implementation, we need to add:
1. **Real-time disconnection feedback** - Show users immediately when connection is lost
2. **Persistent reconnection** - Never give up, keep trying with capped backoff
3. **Manual retry option** - Allow users to trigger immediate retry
4. **Countdown display** - Show time until next reconnection attempt

## Current State
The previous implementation added:
- `verifyConnection()` ping-based connection check
- `forceReconnect()` for clean reconnection
- Foreground return triggers verification and reconnect
- Views observe `connectionState` and refresh on `.connected`

**Gap**: Views only react to becoming connected, not to disconnection. Auto-reconnect gives up after 5 attempts (~26 seconds).

---

## Implementation Plan

### Phase 1: Update ConnectionState Enum

**File:** `WebSocketService.swift`

Enhance the state to include timing info for UI:

```swift
enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, nextRetrySeconds: Int)  // Enhanced with countdown
    case failed(reason: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }
}
```

### Phase 2: Persistent Reconnection Logic

**File:** `WebSocketService.swift`

Replace limited retry with persistent reconnection:

```swift
// Change constants
private let maxReconnectDelay: TimeInterval = 30.0  // Cap at 30 seconds
private let initialReconnectDelay: TimeInterval = 1.0  // Start at 1 second

// Rewrite handleDisconnect()
private func handleDisconnect() async {
    // ... cleanup code stays same ...

    // Don't reconnect if in background
    if isInBackground {
        connectionState = .disconnected
        return
    }

    // Start persistent reconnection
    await startPersistentReconnection()
}

/// Persistent reconnection - never gives up
private func startPersistentReconnection() async {
    reconnectAttempts += 1

    // Exponential backoff capped at maxReconnectDelay
    // 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s...
    let delay = min(maxReconnectDelay, initialReconnectDelay * pow(2.0, Double(min(reconnectAttempts - 1, 10))))

    // Countdown loop - updates UI every second
    var remainingSeconds = Int(delay)
    while remainingSeconds > 0 && !isConnectedFlag && !isInBackground {
        connectionState = .reconnecting(attempt: reconnectAttempts, nextRetrySeconds: remainingSeconds)
        try? await Task.sleep(for: .seconds(1))
        remainingSeconds -= 1
    }

    guard !isConnectedFlag && !isInBackground else { return }

    await connect()
}

/// Manual retry from UI
func manualRetry() async {
    guard !isConnectedFlag && !isConnectionInProgress else { return }
    reconnectAttempts = 0
    connectionState = .connecting
    await connect()
}
```

### Phase 3: RPCClient Proxy Method

**File:** `RPCClient.swift`

```swift
/// Manual retry triggered from UI
func manualRetry() async {
    await webSocket?.manualRetry()
}
```

### Phase 4: Connection Status Pill Component

**New File:** `Views/Components/ConnectionStatusPill.swift`

A pill notification that appears at the bottom of the chat as the "latest event":
- Only visible when NOT connected (disconnected, connecting, reconnecting)
- Briefly shows "Connected" when connection established, then fades out
- Fluid animations between states
- Tappable for manual retry

```swift
@available(iOS 26.0, *)
struct ConnectionStatusPill: View {
    let connectionState: ConnectionState
    let onRetry: () async -> Void

    @State private var showConnectedBriefly = false
    @State private var previousState: ConnectionState = .disconnected

    var body: some View {
        Group {
            if shouldShow {
                pillContent
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: connectionState)
        .onChange(of: connectionState) { oldState, newState in
            handleStateTransition(from: oldState, to: newState)
        }
    }

    private var shouldShow: Bool {
        switch connectionState {
        case .connected:
            return showConnectedBriefly  // Only show briefly after reconnecting
        case .disconnected, .connecting, .reconnecting, .failed:
            return true
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        Button {
            Task { await onRetry() }
        } label: {
            HStack(spacing: 8) {
                // Status icon/indicator
                statusIcon

                // Status text
                Text(statusText)
                    .font(TronTypography.mono(size: TronTypography.sizeCaption, weight: .medium))

                // Countdown for reconnecting
                if case .reconnecting(_, let seconds) = connectionState {
                    Text("(\(seconds)s)")
                        .font(TronTypography.mono(size: TronTypography.sizeCaption))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(connectionState.isConnected)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch connectionState {
        case .disconnected:
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
        case .connecting, .reconnecting:
            ProgressView()
                .scaleEffect(0.6)
                .tint(.white)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var statusText: String {
        switch connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .reconnecting(let attempt, _): return "Reconnecting #\(attempt)"
        case .connected: return "Connected"
        case .failed: return "Tap to retry"
        }
    }

    private var backgroundColor: Color {
        switch connectionState {
        case .connected: return .tronEmerald.opacity(0.9)
        case .failed: return .tronError.opacity(0.9)
        default: return .tronPhthaloGreen.opacity(0.9)
        }
    }

    private var foregroundColor: Color {
        .white
    }

    private func handleStateTransition(from oldState: ConnectionState, to newState: ConnectionState) {
        // When transitioning TO connected from a non-connected state
        if newState.isConnected && !oldState.isConnected {
            showConnectedBriefly = true
            // Hide after 2 seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showConnectedBriefly = false
                    }
                }
            }
        }
    }
}
```

### Phase 5: Integrate Pill into ChatView

**File:** `ChatView.swift`

Add the connection status pill as the last item in the ScrollView, after all messages:

```swift
// Inside the ScrollView, after ForEach(messages)
ConnectionStatusPill(
    connectionState: viewModel.connectionState,
    onRetry: { await appState.rpcClient.manualRetry() }
)
.frame(maxWidth: .infinity)
.padding(.top, 8)
.id("connectionStatusPill")
```

The pill will:
- Appear at the bottom of the chat (like a new "event")
- Auto-scroll into view when it appears (existing scroll logic handles this)
- Animate smoothly between states
- Show "Connected" briefly then fade out when connection restored

### Phase 5b: Other Views (Minimal Changes)

For **NewSessionFlow** and **WorkspaceSelector**:
- Keep existing error handling for connection failures
- The reactive reconnection logic already implemented will refresh them when connected
- No visual pill needed since they already show errors contextually

For **ContentView/SessionSidebar**:
- No visual indicator needed - sessions list will refresh automatically when reconnected

### Phase 6: Update TronMobileApp Foreground Handler

When returning to foreground, also handle `.failed` and `.disconnected` states:

```swift
if newPhase == .active && oldPhase != .active {
    Task {
        // Clear badge
        try? await UNUserNotificationCenter.current().setBadgeCount(0)

        switch appState.rpcClient.connectionState {
        case .connected:
            // Verify connection is still alive
            let isAlive = await appState.rpcClient.verifyConnection()
            if !isAlive {
                await appState.rpcClient.forceReconnect()
            }
        case .disconnected, .failed:
            // Trigger reconnection
            await appState.rpcClient.manualRetry()
        case .connecting, .reconnecting:
            // Already in progress, let it continue
            break
        }
    }
}
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `WebSocketService.swift` | Update ConnectionState enum, replace handleDisconnect with persistent reconnection, add manualRetry() |
| `RPCClient.swift` | Add manualRetry() proxy method |
| **NEW** `ConnectionStatusPill.swift` | Create pill component for chat flow |
| `ChatView.swift` | Add ConnectionStatusPill at end of message list |
| `TronMobileApp.swift` | Enhanced foreground handler for all states |

---

## Data Flow

```
Server Dies / Network Lost
         │
         ▼
   receiveLoop() throws error
         │
         ▼
   handleDisconnect()
   - Cleans up WebSocket
   - Starts persistent reconnection
         │
         ▼
   connectionState = .reconnecting(attempt: 1, nextRetrySeconds: 1)
         │
         ├─────────────────────────────────────┐
         ▼                                     ▼
   WebSocketService                      ChatView
   - Countdown loop                      - Pill appears at bottom
   - Updates state every second          - Shows "Reconnecting #1 (Xs)"
   - Attempts connect()                  - Updates countdown in real-time
         │
         ├── Success ──────────────────────────┐
         │                                     ▼
         │                               ChatView
         │                               - Pill shows "Connected" (green)
         │                               - After 2s, pill fades out
         │                               - Session resumes
         │
         └── Failure ──────────────────────────┐
                                               ▼
                                         Increment attempt
                                         - Double delay (capped at 30s)
                                         - Loop back to countdown
```

---

## Verification Checklist

- [ ] Kill server while in ChatView → pill appears at bottom with "Disconnected"
- [ ] Reconnection starts → pill shows "Reconnecting #1 (1s)", countdown updates
- [ ] Restart server → pill turns green "Connected", fades out after 2s
- [ ] Kill server for 2+ min → reconnection continues, attempts increment, delay caps at 30s
- [ ] Tap pill → immediate reconnection attempt (resets attempt counter)
- [ ] Background during reconnection → pauses, resumes on foreground
- [ ] Return to foreground in failed state → auto-triggers retry
- [ ] Network off → pill shows status, reconnects when network returns
- [ ] When connected normally → NO pill visible (clean UI)

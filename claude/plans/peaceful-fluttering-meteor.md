# Follow-Up Prompt Suggestions Feature

## Overview

Add intelligent follow-up prompt suggestions that appear after an agent completes responding or when resuming a session. A background Haiku 4.5 call generates 2 short suggestions (max 4 words each) displayed as tappable chips above the input bar.

**Trigger conditions:**
1. After agent completes responding (`.complete` event)
2. After resuming an existing session (only if agent not running)

**UX behavior:**
- Input bar area expands up to show chip row
- Chips animate in with stagger
- X button to left dismisses all chips
- Chip row is horizontally scrollable
- Tapping chip populates input (chip stays visible)
- Sending ANY prompt clears chips

**Configurable:**
- Toggle in Settings to disable completely
- Enabled by default
- Uses `@AppStorage` for persistence

---

## Architecture Alignment

This feature follows established patterns from recent refactoring:

| Pattern | How We Follow It |
|---------|------------------|
| **Extracted State Objects** | New `FollowUpSuggestionState` alongside `browserState`, `todoState`, etc. |
| **InputBar State/Config/Actions** | Add to `InputBarConfig` (read-only suggestions) and `InputBarActions` (callbacks) |
| **RPC Handler Pattern** | New `suggest.handler.ts` with `createSuggestHandlers()` factory |
| **Adapter Pattern** | New `suggest.adapter.ts` that makes Anthropic API call |
| **Unified Event Stream** | No changes needed - this is RPC, not events |
| **Settings Pattern** | Use `@AppStorage` with toggle in Settings (like `confirmArchive`) |
| **Test-Driven** | Write tests for handler, adapter, and iOS state |

---

## Phase 1: Server-Side Implementation

### 1.1 Create Adapter: `packages/agent/src/gateway/rpc/adapters/suggest.adapter.ts`

```typescript
/**
 * @fileoverview Suggest Adapter
 *
 * Provides follow-up prompt suggestions using Haiku 4.5.
 * Standalone adapter (no orchestrator dependency).
 */

import Anthropic from '@anthropic-ai/sdk';
import { createLogger } from '../../../logging/logger.js';

const logger = createLogger('suggest-adapter');

export interface SuggestFollowUpsParams {
  lastUserPrompt: string;
  lastAssistantResponse: string;
}

export interface SuggestFollowUpsResult {
  suggestions: string[];
}

export interface SuggestManagerAdapter {
  getFollowUpSuggestions(params: SuggestFollowUpsParams): Promise<SuggestFollowUpsResult>;
}

const SYSTEM_PROMPT = `You suggest follow-up questions. Given a user's message and assistant's response, provide exactly 2 short follow-up questions the user might ask next. Each MUST be 4 words or fewer. Output only the questions, one per line, no numbering or bullets.`;

export function createSuggestAdapter(): SuggestManagerAdapter {
  return {
    async getFollowUpSuggestions(params): Promise<SuggestFollowUpsResult> {
      const anthropic = new Anthropic();

      const userContent = `User: "${params.lastUserPrompt.substring(0, 200)}"
Assistant: "${params.lastAssistantResponse.substring(0, 500)}"

Suggest 2 follow-ups:`;

      try {
        const response = await anthropic.messages.create({
          model: 'claude-haiku-4-5-20251001',
          max_tokens: 60,
          system: SYSTEM_PROMPT,
          messages: [{ role: 'user', content: userContent }],
        });

        const text = response.content[0].type === 'text' ? response.content[0].text : '';
        const suggestions = text
          .split('\n')
          .map((s) => s.trim())
          .filter((s) => s.length > 0 && s.length <= 40)
          .slice(0, 2);

        logger.debug(`Generated ${suggestions.length} follow-up suggestions`);
        return { suggestions };
      } catch (error) {
        logger.warning(`Failed to generate suggestions: ${error}`);
        return { suggestions: [] };
      }
    },
  };
}
```

### 1.2 Create Handler: `packages/agent/src/rpc/handlers/suggest.handler.ts`

```typescript
/**
 * @fileoverview Suggest RPC Handlers
 *
 * Handlers for suggest.* RPC methods:
 * - suggest.getFollowUps: Get follow-up prompt suggestions
 */

import type { RpcRequest } from '../types.js';
import type { RpcContext } from '../handler.js';
import { MethodRegistry, type MethodRegistration, type MethodHandler } from '../registry.js';

export interface SuggestGetFollowUpsParams {
  lastUserPrompt: string;
  lastAssistantResponse: string;
}

/**
 * Handle suggest.getFollowUps request
 */
export async function handleSuggestGetFollowUps(
  request: RpcRequest,
  context: RpcContext
): Promise<{ suggestions: string[] }> {
  const params = request.params as SuggestGetFollowUpsParams | undefined;

  if (!params?.lastUserPrompt || !params?.lastAssistantResponse) {
    throw new Error('lastUserPrompt and lastAssistantResponse are required');
  }

  if (!context.suggestManager) {
    throw new Error('Suggest manager not available');
  }

  return context.suggestManager.getFollowUpSuggestions({
    lastUserPrompt: params.lastUserPrompt,
    lastAssistantResponse: params.lastAssistantResponse,
  });
}

/**
 * Create suggest handler registrations
 */
export function createSuggestHandlers(): MethodRegistration[] {
  const getFollowUpsHandler: MethodHandler = async (request, context) => {
    return handleSuggestGetFollowUps(request, context);
  };

  return [
    {
      method: 'suggest.getFollowUps',
      handler: getFollowUpsHandler,
      options: {
        requiredParams: ['lastUserPrompt', 'lastAssistantResponse'],
        requiredManagers: ['suggestManager'],
        description: 'Get follow-up prompt suggestions using Haiku 4.5',
      },
    },
  ];
}
```

### 1.3 Update RpcContext: `packages/agent/src/rpc/handler.ts`

Add to interface (around line 88):
```typescript
/** Suggest manager for follow-up prompts (optional) */
suggestManager?: SuggestManagerAdapter;
```

Add import and registration in constructor (around line 379):
```typescript
import { createSuggestHandlers } from './handlers/suggest.handler.js';
// In constructor:
this.registry.registerAll(createSuggestHandlers());
```

### 1.4 Update Context Factory: `packages/agent/src/gateway/rpc/context-factory.ts`

Add import and registration:
```typescript
import { createSuggestAdapter } from './adapters/suggest.adapter.js';

// In createRpcContext(), add with standalone adapters (around line 132):
context.suggestManager = createSuggestAdapter();
```

### 1.5 Create Test: `packages/agent/src/rpc/handlers/__tests__/suggest.handler.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleSuggestGetFollowUps, createSuggestHandlers } from '../suggest.handler.js';
import type { RpcRequest } from '../../types.js';
import type { RpcContext } from '../../handler.js';

describe('Suggest Handler', () => {
  let mockContext: Partial<RpcContext>;

  beforeEach(() => {
    mockContext = {
      suggestManager: {
        getFollowUpSuggestions: vi.fn().mockResolvedValue({
          suggestions: ['How does it work?', 'Show me more'],
        }),
      },
    };
  });

  describe('handleSuggestGetFollowUps', () => {
    it('should return suggestions from manager', async () => {
      const request: RpcRequest = {
        id: 'test-1',
        method: 'suggest.getFollowUps',
        params: {
          lastUserPrompt: 'Help me with X',
          lastAssistantResponse: 'Here is how to do X...',
        },
      };

      const result = await handleSuggestGetFollowUps(request, mockContext as RpcContext);

      expect(result.suggestions).toHaveLength(2);
      expect(mockContext.suggestManager?.getFollowUpSuggestions).toHaveBeenCalledWith({
        lastUserPrompt: 'Help me with X',
        lastAssistantResponse: 'Here is how to do X...',
      });
    });

    it('should throw if manager not available', async () => {
      const request: RpcRequest = {
        id: 'test-2',
        method: 'suggest.getFollowUps',
        params: { lastUserPrompt: 'test', lastAssistantResponse: 'test' },
      };

      await expect(
        handleSuggestGetFollowUps(request, {} as RpcContext)
      ).rejects.toThrow('Suggest manager not available');
    });

    it('should throw if params missing', async () => {
      const request: RpcRequest = {
        id: 'test-3',
        method: 'suggest.getFollowUps',
        params: {},
      };

      await expect(
        handleSuggestGetFollowUps(request, mockContext as RpcContext)
      ).rejects.toThrow('lastUserPrompt and lastAssistantResponse are required');
    });
  });

  describe('createSuggestHandlers', () => {
    it('should return registration with correct options', () => {
      const handlers = createSuggestHandlers();

      expect(handlers).toHaveLength(1);
      expect(handlers[0].method).toBe('suggest.getFollowUps');
      expect(handlers[0].options?.requiredParams).toContain('lastUserPrompt');
      expect(handlers[0].options?.requiredManagers).toContain('suggestManager');
    });
  });
});
```

---

## Phase 2: iOS State Management

### 2.1 Create State: `packages/ios-app/Sources/ViewModels/State/FollowUpSuggestionState.swift`

Follows pattern of other state objects (`BrowserState`, `TodoState`, etc.):

```swift
import Foundation

/// State for follow-up prompt suggestions
/// Follows extracted state object pattern from ChatViewModel
@Observable
final class FollowUpSuggestionState {
    // MARK: - State

    /// Current suggestions (empty if none/dismissed)
    var suggestions: [String] = []

    /// Whether suggestions are currently loading
    var isLoading: Bool = false

    /// Whether user has dismissed suggestions for this turn
    private var isDismissed: Bool = false

    // MARK: - Computed Properties

    /// Whether suggestions should be visible in UI
    var isVisible: Bool {
        !suggestions.isEmpty && !isDismissed && !isLoading
    }

    // MARK: - Actions

    /// Clear all state (called when user sends a prompt)
    func clear() {
        suggestions = []
        isLoading = false
        isDismissed = false
    }

    /// Dismiss suggestions (called when user taps X)
    func dismiss() {
        isDismissed = true
        suggestions = []
    }

    /// Start loading suggestions
    func startLoading() {
        isLoading = true
        isDismissed = false
    }

    /// Set suggestions from server response
    func setSuggestions(_ newSuggestions: [String]) {
        suggestions = newSuggestions
        isLoading = false
    }

    /// Handle error by clearing state
    func handleError() {
        suggestions = []
        isLoading = false
    }
}
```

### 2.2 Add to ChatViewModel: `packages/ios-app/Sources/ViewModels/ChatViewModel.swift`

Add alongside other extracted state objects (around line 68):
```swift
/// Follow-up suggestion state
let followUpState = FollowUpSuggestionState()
```

---

## Phase 3: iOS RPC Integration

### 3.1 Update RPCTypes: `packages/ios-app/Sources/Models/RPCTypes.swift`

Add new types:
```swift
// MARK: - Suggest Types

struct FollowUpSuggestionsParams: Codable {
    let lastUserPrompt: String
    let lastAssistantResponse: String
}

struct FollowUpSuggestionsResult: Codable {
    let suggestions: [String]
}
```

### 3.2 Update RPCClient: `packages/ios-app/Sources/Services/RPCClient.swift`

Add method (in MARK: - Suggest Methods section):
```swift
// MARK: - Suggest Methods

func getFollowUpSuggestions(
    lastUserPrompt: String,
    lastAssistantResponse: String
) async throws -> FollowUpSuggestionsResult {
    guard let ws = webSocket else {
        throw RPCClientError.notConnected
    }
    let params = FollowUpSuggestionsParams(
        lastUserPrompt: lastUserPrompt,
        lastAssistantResponse: lastAssistantResponse
    )
    return try await ws.send(method: "suggest.getFollowUps", params: params)
}
```

### 3.3 Update RPCClientProtocol: `packages/ios-app/Sources/Protocols/RPCClientProtocol.swift`

Add to protocol:
```swift
func getFollowUpSuggestions(
    lastUserPrompt: String,
    lastAssistantResponse: String
) async throws -> FollowUpSuggestionsResult
```

---

## Phase 4: iOS UI Components

### 4.1 Create UI: `packages/ios-app/Sources/Views/InputBar/FollowUpSuggestionRow.swift`

```swift
import SwiftUI

// MARK: - Follow-Up Chip

@available(iOS 26.0, *)
struct FollowUpChip: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb.fill")
                    .font(TronTypography.sans(size: TronTypography.sizeSM, weight: .semibold))
                    .foregroundStyle(.tronEmerald)

                Text(text)
                    .font(TronTypography.filePath)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(Color.tronEmerald.opacity(0.3)),
                        in: .capsule
                    )
            }
            .overlay(
                Capsule()
                    .strokeBorder(Color.tronEmerald.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Follow-Up Suggestion Row

@available(iOS 26.0, *)
struct FollowUpSuggestionRow: View {
    let suggestions: [String]
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var visibleCount = 0

    var body: some View {
        HStack(spacing: 8) {
            // Dismiss button (X)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(TronTypography.sans(size: 16, weight: .medium))
                    .foregroundStyle(.tronSlate.opacity(0.6))
            }
            .buttonStyle(.plain)

            // Scrollable chip row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        if index < visibleCount {
                            FollowUpChip(text: suggestion, onTap: { onSelect(suggestion) })
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .scale(scale: 0.6).combined(with: .opacity)
                                ))
                        }
                    }
                }
            }
        }
        .frame(height: 36)
        .onAppear {
            animateChipsIn()
        }
    }

    private func animateChipsIn() {
        visibleCount = 0
        for i in 0..<suggestions.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    visibleCount = i + 1
                }
            }
        }
    }
}
```

---

## Phase 5: Integration

### 5.1 Update InputBarState: `packages/ios-app/Sources/ViewModels/State/InputBarState.swift`

**Add to InputBarConfig** (around line 77):
```swift
// MARK: - Follow-up Suggestions
let followUpSuggestions: [String]
```

Update init with default:
```swift
followUpSuggestions: [String] = []
```

**Add to InputBarActions** (around line 143):
```swift
// MARK: - Follow-up Suggestions
let onFollowUpSelect: ((String) -> Void)?
let onFollowUpDismiss: (() -> Void)?
```

Update init with defaults:
```swift
onFollowUpSelect: ((String) -> Void)? = nil,
onFollowUpDismiss: (() -> Void)? = nil
```

### 5.2 Update InputBar: `packages/ios-app/Sources/Views/InputBar/InputBar.swift`

Insert between spell mention popup and contentArea (around line 111):
```swift
// Follow-up suggestions row
if !config.followUpSuggestions.isEmpty {
    FollowUpSuggestionRow(
        suggestions: config.followUpSuggestions,
        onSelect: { suggestion in
            actions.onFollowUpSelect?(suggestion)
        },
        onDismiss: {
            actions.onFollowUpDismiss?()
        }
    )
    .padding(.horizontal, 16)
    .transition(.move(edge: .bottom).combined(with: .opacity))
}
```

Add animation modifier (around line 231):
```swift
.animation(.spring(response: 0.35, dampingFraction: 0.8), value: config.followUpSuggestions.count)
```

### 5.3 Update ChatView: `packages/ios-app/Sources/Views/ChatView.swift`

**Add to InputBarConfig construction** (around line 170):
```swift
followUpSuggestions: viewModel.followUpState.isVisible ? viewModel.followUpState.suggestions : []
```

**Add to InputBarActions construction** (around line 227):
```swift
onFollowUpSelect: { suggestion in
    viewModel.inputText = suggestion
},
onFollowUpDismiss: {
    viewModel.followUpState.dismiss()
}
```

**Add to onSend closure** (around line 174, at start):
```swift
// Clear follow-up suggestions when sending any prompt
viewModel.followUpState.clear()
```

### 5.4 Update ChatViewModel+Events: `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`

**Add to end of `handleComplete()`** (before closing brace, around line 696):
```swift
// Fetch follow-up suggestions in background
fetchFollowUpSuggestions()
```

**Add new method** (after `handleComplete()`):
```swift
/// Fetch follow-up prompt suggestions using Haiku
private func fetchFollowUpSuggestions() {
    // Find the last user and assistant messages
    guard let lastUserMessage = messages.last(where: { $0.role == .user }),
          let lastAssistantMessage = messages.last(where: { $0.role == .assistant }) else {
        return
    }

    // Extract text content using established pattern
    let userText = lastUserMessage.content.textContent
    let assistantText = lastAssistantMessage.content.textContent

    // Skip if either is empty
    guard !userText.isEmpty, !assistantText.isEmpty else { return }

    followUpState.startLoading()

    Task {
        do {
            let result = try await rpcClient.getFollowUpSuggestions(
                lastUserPrompt: userText,
                lastAssistantResponse: assistantText
            )
            await MainActor.run {
                followUpState.setSuggestions(result.suggestions)
            }
        } catch {
            logger.warning("Failed to fetch follow-up suggestions: \(error)", category: .rpc)
            await MainActor.run {
                followUpState.handleError()
            }
        }
    }
}
```

### 5.5 Update ChatViewModel+Connection: `packages/ios-app/Sources/ViewModels/ChatViewModel+Connection.swift`

**Add after `fetchTodosOnResume()`** (around line 52):
```swift
// Fetch follow-up suggestions for resumed session (only if agent not running)
if !isProcessing {
    fetchFollowUpSuggestions()
}
```

---

## Phase 6: Settings Configuration

### 6.1 Update SettingsView: `packages/ios-app/Sources/Views/SettingsView.swift`

**Add AppStorage property** (around line 18):
```swift
@AppStorage("followUpSuggestionsEnabled") private var followUpSuggestionsEnabled = true
```

**Add new "Features" section** (after Data section, around line 136):
```swift
// Features Section
Section {
    Toggle(isOn: $followUpSuggestionsEnabled) {
        Label("Follow-up suggestions", systemImage: "lightbulb")
            .font(TronTypography.subheadline)
    }
} header: {
    Text("Features")
        .font(TronTypography.caption)
} footer: {
    Text("Show suggested follow-up prompts after the agent responds.")
        .font(TronTypography.caption2)
}
.listSectionSpacing(16)
```

**Add to `resetToDefaults()`** (around line 242):
```swift
followUpSuggestionsEnabled = true
```

### 6.2 Update ChatViewModel: `packages/ios-app/Sources/ViewModels/ChatViewModel.swift`

**Add AppStorage property** (around line 30):
```swift
@AppStorage("followUpSuggestionsEnabled") private var followUpSuggestionsEnabled = true
```

### 6.3 Update fetchFollowUpSuggestions in ChatViewModel+Events.swift

**Add check at start of method**:
```swift
/// Fetch follow-up prompt suggestions using Haiku
private func fetchFollowUpSuggestions() {
    // Check if feature is enabled
    guard followUpSuggestionsEnabled else { return }

    // Find the last user and assistant messages
    guard let lastUserMessage = messages.last(where: { $0.role == .user }),
    // ... rest of method
```

---

## Phase 7: Tests

### 7.1 iOS State Test: `packages/ios-app/Tests/ViewModels/FollowUpSuggestionStateTests.swift`

```swift
import XCTest
@testable import TronMobile

@MainActor
final class FollowUpSuggestionStateTests: XCTestCase {

    var state: FollowUpSuggestionState!

    override func setUp() async throws {
        state = FollowUpSuggestionState()
    }

    func testInitialState() {
        XCTAssertTrue(state.suggestions.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.isVisible)
    }

    func testSetSuggestionsMakesVisible() {
        state.setSuggestions(["Test 1", "Test 2"])

        XCTAssertEqual(state.suggestions.count, 2)
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.isVisible)
    }

    func testDismissHidesSuggestions() {
        state.setSuggestions(["Test 1", "Test 2"])
        state.dismiss()

        XCTAssertTrue(state.suggestions.isEmpty)
        XCTAssertFalse(state.isVisible)
    }

    func testClearResetsAll() {
        state.setSuggestions(["Test 1"])
        state.clear()

        XCTAssertTrue(state.suggestions.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.isVisible)
    }

    func testLoadingPreventsVisibility() {
        state.startLoading()

        XCTAssertTrue(state.isLoading)
        XCTAssertFalse(state.isVisible)
    }

    func testHandleErrorClearsState() {
        state.startLoading()
        state.handleError()

        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.suggestions.isEmpty)
    }
}
```

---

## File Summary

### Server-Side (5 files)
| File | Change |
|------|--------|
| `packages/agent/src/gateway/rpc/adapters/suggest.adapter.ts` | **NEW** - Haiku 4.5 API call |
| `packages/agent/src/rpc/handlers/suggest.handler.ts` | **NEW** - RPC handler |
| `packages/agent/src/rpc/handlers/__tests__/suggest.handler.test.ts` | **NEW** - Handler tests |
| `packages/agent/src/rpc/handler.ts` | Add to RpcContext + import handler |
| `packages/agent/src/gateway/rpc/context-factory.ts` | Register adapter |

### iOS-Side (12 files)
| File | Change |
|------|--------|
| `packages/ios-app/Sources/ViewModels/State/FollowUpSuggestionState.swift` | **NEW** - State object |
| `packages/ios-app/Sources/Views/InputBar/FollowUpSuggestionRow.swift` | **NEW** - UI component |
| `packages/ios-app/Tests/ViewModels/FollowUpSuggestionStateTests.swift` | **NEW** - State tests |
| `packages/ios-app/Sources/Models/RPCTypes.swift` | Add request/response types |
| `packages/ios-app/Sources/Services/RPCClient.swift` | Add RPC method |
| `packages/ios-app/Sources/Protocols/RPCClientProtocol.swift` | Add protocol method |
| `packages/ios-app/Sources/ViewModels/State/InputBarState.swift` | Extend Config + Actions |
| `packages/ios-app/Sources/Views/InputBar/InputBar.swift` | Integrate suggestion row |
| `packages/ios-app/Sources/Views/ChatView.swift` | Wire config/actions |
| `packages/ios-app/Sources/Views/SettingsView.swift` | Add toggle to disable feature |
| `packages/ios-app/Sources/ViewModels/ChatViewModel.swift` | Add followUpState + AppStorage |
| `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift` | Trigger on complete + check setting |
| `packages/ios-app/Sources/ViewModels/ChatViewModel+Connection.swift` | Trigger on resume |
| `packages/ios-app/TronMobile.xcodeproj/project.pbxproj` | Add new files |

---

## Verification

### Build & Test
```bash
bun run build && bun run test
```

### Manual Testing
1. **New session flow:**
   - Start new session
   - Send a prompt, wait for response
   - Verify chips appear above input bar (~1s delay)
   - Tap chip → verify input populated, chips stay visible
   - Tap X → verify chips dismissed
   - Send prompt → verify chips cleared

2. **Resume session flow:**
   - Close app during active session
   - Reopen and resume session
   - Verify chips appear for last exchange (if not processing)

3. **Settings toggle:**
   - Open Settings → Features section
   - Toggle off "Follow-up suggestions"
   - Send a new prompt → verify NO chips appear
   - Toggle back on → verify chips appear again

4. **Edge cases:**
   - Very short responses (< 50 chars)
   - Tool-only responses (no text)
   - Session resume while agent is running (no chips)

### Test Commands
```bash
# Server tests
bun run test:agent --grep "Suggest"

# iOS tests (Xcode)
# Run FollowUpSuggestionStateTests in Xcode Test Navigator
```

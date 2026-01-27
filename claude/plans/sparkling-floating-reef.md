# Plan: Replace Browser Tool with AgentWebBrowser using agent-browser

## Summary

Rename `Browser` tool to `AgentWebBrowser` and replace the custom Playwright/CDP implementation with the [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) library. The iOS app frame streaming format will be preserved.

## Changes

### 1. Install agent-browser dependency

**File:** `packages/server/package.json`
- Add `"agent-browser": "^0.6.0"`

### 2. Rename and update the tool (core package)

**File:** `packages/core/src/tools/browser.ts` → **rename to** `agent-web-browser.ts`
- Rename class `BrowserTool` → `AgentWebBrowserTool`
- Update `readonly name = 'AgentWebBrowser'`
- Update description to reflect new name
- Keep `BrowserDelegate` interface (no changes needed)

**File:** `packages/core/src/tools/index.ts`
- Update export: `BrowserTool` → `AgentWebBrowserTool`
- Update import path: `browser.js` → `agent-web-browser.js`

### 3. Replace BrowserService with agent-browser wrapper (server package)

**File:** `packages/server/src/browser/browser-service.ts`

Replace the custom Playwright implementation with a wrapper around `BrowserManager` from agent-browser:

```typescript
import { BrowserManager } from 'agent-browser';

export class BrowserService extends EventEmitter {
  private managers = new Map<string, BrowserManager>();

  async createSession(sessionId: string) {
    const manager = new BrowserManager();
    await manager.launch({ headless: true });
    await manager.setViewport(1280, 800);  // Keep iOS-compatible size
    this.managers.set(sessionId, manager);
  }

  async startScreencast(sessionId: string, options) {
    const manager = this.managers.get(sessionId);
    await manager.startScreencast((frame) => {
      // Transform to Tron frame format
      this.emit('browser.frame', {
        sessionId,                    // string (Tron session ID)
        data: frame.data,             // base64 JPEG
        frameId: frame.sessionId,     // number (CDP session ID)
        timestamp: Date.now(),
        metadata: frame.metadata,
      });
    }, options);
  }

  async execute(sessionId, action, params) {
    const manager = this.managers.get(sessionId);
    switch (action) {
      case 'navigate': return manager.navigate(params.url);
      case 'click': return manager.click(params.selector);
      case 'fill': return manager.fill(params.selector, params.value);
      case 'snapshot': return manager.getSnapshot();
      // ... other actions
    }
  }
}
```

### 4. Update agent-factory imports

**File:** `packages/server/src/orchestrator/agent-factory.ts`
- Line 21: `BrowserTool` → `AgentWebBrowserTool`
- Line 130: `new BrowserTool(...)` → `new AgentWebBrowserTool(...)`

### 5. Update tests

**File:** `packages/core/test/tools/browser.test.ts` → **rename to** `agent-web-browser.test.ts`
- Update imports and class references

## Frame Format Compatibility

agent-browser frame format → Tron frame format (iOS compatible):

| agent-browser | Tron (iOS expects) |
|---------------|-------------------|
| `frame.data` | `data` (base64 JPEG) |
| `frame.sessionId` (number) | `frameId` (number) |
| `frame.metadata.*` | `metadata.*` |
| N/A | `sessionId` (string, Tron session) |
| N/A | `timestamp` (add `Date.now()`) |

## New Actions to Add

Beyond the current actions, expose these agent-browser capabilities:

| Action | Method | Description |
|--------|--------|-------------|
| `goBack` | `manager.goBack()` | Navigate back in history |
| `goForward` | `manager.goForward()` | Navigate forward in history |
| `reload` | `manager.reload()` | Reload current page |
| `hover` | `page.hover(selector)` | Hover over element (trigger hover states) |
| `pressKey` | `page.keyboard.press(key)` | Press keyboard key (shortcuts) |
| `find` | Semantic locators | Find elements by role, text, label |
| `pdf` | `page.pdf()` | Generate PDF of page |
| `getText` | `page.innerText()` | Extract text content |
| `getAttribute` | `locator.getAttribute()` | Get element attribute |

Update tool description in `agent-web-browser.ts` to document all new actions.

## Migration Notes

- This is a **breaking change** for existing sessions using `Browser` tool
- Sessions must be restarted to use the new `AgentWebBrowser` tool
- No iOS app changes needed - frame format is preserved

## Verification

```bash
bun run build && bun run test
```

Then test with iOS app:
1. Start a session
2. Call `AgentWebBrowser` with `navigate` action
3. Verify frames stream to iOS app
4. Test `snapshot`, `click`, `fill` actions

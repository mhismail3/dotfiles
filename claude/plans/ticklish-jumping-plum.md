# Clone GitHub Repo Feature for iOS New Session Flow

## Overview
Add the ability to paste a GitHub repo URL in the iOS app's new session sheet, clone it to a specified folder (defaulting to `~/Downloads/projects`), and start a session in the cloned workspace.

## Implementation Plan

### 1. Server-Side: New `git.clone` RPC Handler

**File: `packages/core/src/rpc/handlers/git.handler.ts`** (NEW)

Create a new handler following the pattern in `filesystem.handler.ts`:

```typescript
// Parameters
interface GitCloneParams {
  url: string;         // GitHub URL
  targetPath: string;  // Absolute destination path
}

// Result
interface GitCloneResult {
  success: boolean;
  path: string;        // Final cloned path
  repoName: string;    // Extracted repo name
  error?: string;
}
```

Implementation:
- Validate URL is a valid GitHub HTTPS URL
- Extract repo name from URL
- Validate target path (no traversal, parent exists)
- Execute `git clone --depth 1 <url> <targetPath>` via `child_process.spawn`
- 5-minute timeout for large repos
- Return success/error result

**File: `packages/core/src/rpc/handlers/index.ts`** - Export git handlers
**File: `packages/core/src/rpc/types.ts`** - Add type definitions

---

### 2. iOS App: URL Parser Utility

**File: `packages/ios-app/Sources/Utilities/GitHubURLParser.swift`** (NEW)

```swift
enum GitHubURLParser {
    struct ParseResult {
        let owner: String
        let repoName: String
        let normalizedURL: String  // Always HTTPS
    }

    static func parse(_ url: String) -> ParseResult?
    static func isValid(_ url: String) -> Bool
}
```

Support formats:
- `https://github.com/owner/repo`
- `https://github.com/owner/repo.git`
- `github.com/owner/repo` (auto-prefix https://)

---

### 3. iOS App: RPC Client Extension

**File: `packages/ios-app/Sources/Services/RPCClient.swift`**

Add new method:
```swift
func cloneRepository(url: String, targetPath: String) async throws -> GitCloneResult
```

**File: `packages/ios-app/Sources/Models/RPCTypes.swift`**

Add types:
```swift
struct GitCloneParams: Encodable { ... }
struct GitCloneResult: Decodable { ... }
```

---

### 4. iOS App: Clone Repo Sheet UI

**File: `packages/ios-app/Sources/Views/Session/CloneRepoSheet.swift`** (NEW)

A new sheet view with:

**State:**
```swift
@State private var repoURL = ""
@State private var destinationPath = ""  // Default: ~/Downloads/projects/<repo-name>
@State private var isCloning = false
@State private var cloneError: String?
@State private var showDestinationPicker = false
```

**UI Layout:**
1. **GitHub URL Input** - TextField with real-time validation
   - Shows extracted repo name when valid
   - Error styling when invalid

2. **Destination Section** - Shows default path, "Change" button opens WorkspaceSelector
   - Default: `$HOME/Downloads/projects/<repo-name>`
   - Monospaced font for path display

3. **Clone Button** - Disabled until URL valid, shows ProgressView while cloning

4. **Error Display** - Glass-styled error message if clone fails

**Styling:** Match existing patterns (`.glassEffect()`, `.tronEmerald`, monospaced fonts)

---

### 5. iOS App: Integration in NewSessionFlow

**File: `packages/ios-app/Sources/Views/Session/NewSessionFlow.swift`**

Add between Workspace and Model sections:

```swift
// New state
@State private var showCloneSheet = false

// New UI section (after line 93, before Model section)
VStack(alignment: .leading, spacing: 10) {
    Text("Or clone a repository")
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.6))

    Button { showCloneSheet = true } label: {
        HStack {
            Image(systemName: "arrow.down.doc.fill")
            Text("Clone from GitHub")
            Spacer()
            Image(systemName: "chevron.right")
        }
        // ... glass styling
    }
}

// New sheet (add after existing sheets)
.sheet(isPresented: $showCloneSheet) {
    CloneRepoSheet(
        rpcClient: rpcClient,
        onCloned: { clonedPath in
            workingDirectory = clonedPath
            // Auto-create session after clone
            createSession()
        }
    )
}
```

---

## Files to Modify/Create

| File | Action | Description |
|------|--------|-------------|
| `packages/core/src/rpc/handlers/git.handler.ts` | CREATE | Git clone RPC handler |
| `packages/core/src/rpc/handlers/index.ts` | MODIFY | Export git handlers |
| `packages/core/src/rpc/types.ts` | MODIFY | Add GitClone types |
| `packages/ios-app/Sources/Utilities/GitHubURLParser.swift` | CREATE | URL validation utility |
| `packages/ios-app/Sources/Views/Session/CloneRepoSheet.swift` | CREATE | Clone UI sheet |
| `packages/ios-app/Sources/Views/Session/NewSessionFlow.swift` | MODIFY | Add clone option |
| `packages/ios-app/Sources/Services/RPCClient.swift` | MODIFY | Add cloneRepository method |
| `packages/ios-app/Sources/Models/RPCTypes.swift` | MODIFY | Add GitClone types |

---

## Error Handling

| Error | User Message | Recovery |
|-------|--------------|----------|
| Invalid URL | "Enter a valid GitHub URL (e.g., github.com/owner/repo)" | Show format hint |
| Destination exists | "Folder already exists. Choose a different name." | Let user change path |
| Clone failed | "Clone failed: [git error]" | Retry button |
| Network error | "Network error. Check your connection." | Retry button |
| Timeout | "Clone timed out. Try again or use a smaller repo." | Retry button |

---

## Verification

1. **Build iOS app** - Ensure no compile errors
2. **Test URL validation** - Try various GitHub URL formats
3. **Test clone flow**:
   - Paste a public repo URL
   - Verify default destination shows correctly
   - Change destination folder
   - Complete clone and verify session starts in cloned workspace
4. **Test error cases** - Invalid URLs, existing folders, network failures

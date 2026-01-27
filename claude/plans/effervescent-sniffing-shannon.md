# Plan: Long-Press Quick Session on New Session Button

## Summary
Add a long-press gesture to the floating "New Session" button on the iOS dashboard that instantly creates a session with configurable defaults (workspace and model from Settings) and navigates directly to the chat view, skipping the new session sheet.

## Key Files to Modify

| File | Change |
|------|--------|
| `packages/ios-app/Sources/Views/SessionSidebar.swift` | Add `onLongPress` callback to `FloatingNewSessionButton` |
| `packages/ios-app/Sources/Views/ContentView.swift` | Wire up long-press handler, implement quick session creation |
| `packages/ios-app/Sources/Views/Settings/SettingsView.swift` | Add "Quick Session" settings section |
| `packages/ios-app/Sources/App/AppState.swift` | Add `quickSessionWorkspace` storage property |

## Implementation Details

### 1. Add Settings Storage (AppState.swift)

Add new `@AppStorage` property for quick session workspace:

```swift
// In AppState class, around line 32:
@AppStorage("quickSessionWorkspace") var quickSessionWorkspace = "/Users/moose/Downloads"
// Note: defaultModel already exists at line 32
```

### 2. Add Quick Session Settings Section (SettingsView.swift)

Add a new "Quick Session" section after the "Data" section:

```swift
// Quick Session Section (for long-press quick create)
Section {
    // Workspace Path
    HStack {
        Label("Workspace", systemImage: "folder")
            .font(TronTypography.subheadline)
        Spacer()
        Text(displayQuickSessionWorkspace)
            .font(TronTypography.codeSM)
            .foregroundStyle(.tronTextSecondary)
            .lineLimit(1)
    }
    .contentShape(Rectangle())
    .onTapGesture {
        showQuickSessionWorkspaceSelector = true
    }

    // Default Model Picker
    ModelPickerMenuContent(
        models: availableModels,
        selectedModelId: $appState.defaultModel,
        isLoading: isLoadingModels
    ) {
        HStack {
            Label("Model", systemImage: "cpu")
                .font(TronTypography.subheadline)
            Spacer()
            Text(selectedModelDisplayName)
                .font(TronTypography.codeSM)
                .foregroundStyle(.tronTextSecondary)
        }
    }
} header: {
    Text("Quick Session")
        .font(TronTypography.caption)
} footer: {
    Text("Long-press the + button to instantly start a session with these defaults.")
        .font(TronTypography.caption2)
}
.listSectionSpacing(16)
```

Add supporting state and computed properties:
```swift
@AppStorage("quickSessionWorkspace") private var quickSessionWorkspace = "/Users/moose/Downloads"
@State private var showQuickSessionWorkspaceSelector = false
@State private var availableModels: [ModelInfo] = []
@State private var isLoadingModels = false

private var displayQuickSessionWorkspace: String {
    quickSessionWorkspace.replacingOccurrences(
        of: "^/Users/[^/]+/",
        with: "~/",
        options: .regularExpression
    )
}

private var selectedModelDisplayName: String {
    if let model = availableModels.first(where: { $0.id == appState.defaultModel }) {
        return model.formattedModelName
    }
    return appState.defaultModel.shortModelName
}
```

Add sheet for workspace selection:
```swift
.sheet(isPresented: $showQuickSessionWorkspaceSelector) {
    WorkspaceSelector(
        rpcClient: rpcClient,
        selectedPath: $quickSessionWorkspace
    )
}
.task {
    await loadModels()
}
```

### 3. Update `FloatingNewSessionButton` (SessionSidebar.swift:125-141)

Add `onLongPress` callback and gesture handling:

```swift
@available(iOS 26.0, *)
struct FloatingNewSessionButton: View {
    let action: () -> Void
    var onLongPress: (() -> Void)? = nil

    var body: some View {
        Image(systemName: "plus")
            .font(TronTypography.sans(size: TronTypography.sizeXXL, weight: .semibold))
            .foregroundStyle(.tronEmerald)
            .frame(width: 56, height: 56)
            .contentShape(Circle())
            .glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.8)).interactive(), in: .circle)
            .onTapGesture { action() }
            .onLongPressGesture(minimumDuration: 0.5) {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                onLongPress?() ?? action()
            }
    }
}
```

### 4. Update SessionSidebar (SessionSidebar.swift)

Add `onNewSessionLongPress` parameter:

```swift
struct SessionSidebar: View {
    // ... existing properties
    let onNewSession: () -> Void
    var onNewSessionLongPress: (() -> Void)? = nil  // New
    // ...

    // In body, update FloatingNewSessionButton:
    FloatingNewSessionButton(
        action: onNewSession,
        onLongPress: onNewSessionLongPress
    )
}
```

### 5. Update WelcomePage (ContentView.swift:416-501)

Add `onNewSessionLongPress` parameter:

```swift
struct WelcomePage: View {
    // ... existing properties
    let onNewSession: () -> Void
    var onNewSessionLongPress: (() -> Void)? = nil  // New
    // ...

    // In body, update FloatingNewSessionButton:
    FloatingNewSessionButton(
        action: onNewSession,
        onLongPress: onNewSessionLongPress
    )
}
```

### 6. Add Quick Session Creation (ContentView.swift)

Add method and wire up callbacks:

```swift
// Add method to ContentView:
private func createQuickSession() {
    Task {
        do {
            let result = try await appState.rpcClient.createSession(
                workingDirectory: appState.quickSessionWorkspace,
                model: appState.defaultModel
            )

            try eventStoreManager.cacheNewSession(
                sessionId: result.sessionId,
                workspaceId: appState.quickSessionWorkspace,
                model: result.model,
                workingDirectory: appState.quickSessionWorkspace
            )

            await MainActor.run {
                selectedSessionId = result.sessionId
            }
        } catch {
            logger.error("Failed to create quick session: \(error)", category: .session)
        }
    }
}

// Update SessionSidebar usage (~line 165):
SessionSidebar(
    selectedSessionId: $selectedSessionId,
    onNewSession: { showNewSessionSheet = true },
    onNewSessionLongPress: { createQuickSession() },
    onDeleteSession: { ... },
    // ...
)

// Update WelcomePage usages (compactWelcomePage ~line 109 and detailContent ~line 205):
WelcomePage(
    onNewSession: { showNewSessionSheet = true },
    onNewSessionLongPress: { createQuickSession() },
    onSettings: { showSettings = true },
    // ...
)
```

### 7. Add quickSessionWorkspace to AppState (AppState.swift)

```swift
// Around line 32, add:
@AppStorage("quickSessionWorkspace") var quickSessionWorkspace = "/Users/moose/Downloads"
```

## Gesture Behavior

- **Tap**: Opens the new session sheet (existing behavior)
- **Long press (0.5s)**: Creates session immediately with settings defaults and navigates to chat
- **Haptic feedback**: Medium impact on successful long press

## Settings Defaults

| Setting | Key | Default Value |
|---------|-----|---------------|
| Quick Session Workspace | `quickSessionWorkspace` | `/Users/moose/Downloads` |
| Default Model | `defaultModel` | `claude-opus-4-5-20251101` (already exists) |

## Verification

1. **Build**: `cd packages/ios-app && xcodebuild -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
2. **Test Settings**:
   - Open Settings → Quick Session section should appear
   - Tap workspace row → Should open folder picker
   - Tap model row → Should show model picker menu
3. **Test Quick Session**:
   - Tap new session button → Should show new session sheet
   - Long-press new session button → Should create session with settings defaults and navigate to chat
   - Session should appear in sidebar with configured workspace
   - Model should match the configured default
4. **Run tests**: `bun run test` from project root

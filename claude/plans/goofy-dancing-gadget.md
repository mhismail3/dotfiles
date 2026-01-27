# Add Liquid Glass Styling to Sidebar Toolbar Buttons

## Issue

On iPad, the sidebar toolbar buttons (logo menu and settings) appear flat without the iOS 26 Liquid Glass effect, while on iPhone they automatically get the glass styling.

## Solution

Apply `.glassEffect()` to the logo Menu and settings Button in `SessionSidebar` toolbar to match the iPhone appearance.

## File to Modify

`packages/ios-app/Sources/Views/SessionSidebar.swift`

## Changes

### 1. Logo Menu (lines 58-72)

Wrap the Menu label content and apply glass effect:

```swift
ToolbarItem(placement: .topBarLeading) {
    Menu {
        ForEach(NavigationMode.allCases, id: \.self) { mode in
            Button {
                onNavigationModeChange?(mode)
            } label: {
                Label(mode.rawValue, systemImage: mode == .agents ? "cpu" : "waveform")
            }
        }
    } label: {
        Image("TronLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 24)
            .padding(8)
            .contentShape(Circle())
    }
    .glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.6)).interactive(), in: .circle)
}
```

### 2. Settings Button (lines 80-86)

Apply glass effect to the settings button:

```swift
ToolbarItem(placement: .topBarTrailing) {
    Button(action: onSettings) {
        Image(systemName: "gearshape")
            .font(TronTypography.sans(size: TronTypography.sizeTitle, weight: .medium))
            .foregroundStyle(.tronEmerald)
            .padding(8)
            .contentShape(Circle())
    }
    .glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.6)).interactive(), in: .circle)
}
```

## Verification

1. Build: `xcodebuild -scheme TronMobile -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build`
2. Run on iPad simulator
3. Verify logo and settings buttons have circular glass backgrounds matching iPhone style

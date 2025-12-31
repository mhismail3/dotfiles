# PWA Icon Setup Plan

## Goal
Add missing icon files so iOS Safari "Add to Home Screen" displays the correct icon and title.

## Source Image
`/Users/moose/Downloads/photo.PNG` - Pixel art orange character in dark cabinet with off-white background.

## Dark Mode Adjustments
- **Change**: Background from off-white (#f5f5f5-ish) → dark (#0f0f0f to match app theme)
- **Keep as-is**: Orange character (do not modify)
- **Keep as-is**: White handle accents on cabinet (small, looks fine on dark)

## Icons to Generate

| File | Size | Notes |
|------|------|-------|
| `apple-touch-icon.png` | 180×180px | iOS home screen |
| `icon-192.png` | 192×192px | Replace existing |
| `icon-512.png` | 512×512px | Android/Chrome manifest |
| `icon-maskable-512.png` | 512×512px | Android adaptive (content in center 80%) |

## Steps

1. **Process source image**: Change background color from off-white to `#0f0f0f`
2. **Generate all 4 icon sizes** from the dark-background version
3. **Copy to** `frontend/public/icons/`
4. **Rebuild**: `cd frontend && npm run build`

## Files to Modify
- `frontend/public/icons/apple-touch-icon.png` - CREATE
- `frontend/public/icons/icon-192.png` - REPLACE
- `frontend/public/icons/icon-512.png` - CREATE
- `frontend/public/icons/icon-maskable-512.png` - CREATE

## Verification
Test on iPhone Safari:
1. Navigate to `http://<mac-mini>:8080`
2. Tap Share → "Add to Home Screen"
3. Confirm dark icon and "Sessions" title appear correctly

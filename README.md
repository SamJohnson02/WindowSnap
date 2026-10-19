# WindowHolder

Native macOS app that places outline holders on screen and snaps other apps' windows into them.

This slice implements holders and snapping only. Automatic removal from a group, close-all, the global close hotkey, and saved frames are not built yet.

## What works now

- **New Holder** adds a borderless panel that fills the screen’s usable area (menu bar and Dock stay clear). A thin bar along the top has Minimize and Delete. It joins every Space and stays available over full-screen apps.
- Drag a window into the holder and release it. It stays at the size and position you dropped it, kept inside the area below the bar. Drag it again to rearrange it. Minimize hides the holder and minimizes every window locked in it. Delete closes those windows. Click the WindowHolder icon in the Dock to bring a minimized holder back.
- **Edit Holders** turns mouse events back on for the whole outline. Drag inside it to move it. Drag an edge or corner to resize it. Press Escape or choose the menu item again to leave edit mode. **Delete Selected Holder** removes the outline you last clicked.
- On left mouse-up, WindowHolder finds the topmost layer-0 window under the pointer (`CGWindowListCopyWindowInfo`), ignoring its own windows. It snaps when more than half of that window lies inside a holder, or when the window covers more than half of the holder. The window is moved and resized to the tile under the pointer with `AXPosition` and `AXSize`, then stored on that holder as an `AXUIElement` plus `CGWindowID`. The menu lists how many windows each holder has snapped.

## Requirements

- macOS 13 or later
- Xcode 15 or later

## App Sandbox is off

Accessibility control of other processes does not work inside the App Sandbox. `WindowHolder/WindowHolder.entitlements` sets `com.apple.security.app-sandbox` to false. Leave the sandbox disabled in Signing & Capabilities. Do not ship a sandboxed build.

## Build and run

1. Open `WindowHolder.xcodeproj`.
2. Select the WindowHolder target. Debug builds are signed with the local **WindowHolder Dev** certificate, and the debug signature is kept stable so the Accessibility grant survives later runs. That certificate lives only in this Mac’s `windowholder-signing` keychain.
3. Turning on “Sign to Run Locally” makes macOS treat every Run as a different app and drop the Accessibility grant. Leave the local certificate in place.
4. Run. WindowHolder appears in the Dock. Click that icon to show the holder again after minimizing it. The WindowHolder menus are at the top of the screen while the app is active, same as any other Mac app.
5. Allow WindowHolder under **System Settings → Privacy & Security → Accessibility**. Quit and relaunch after toggling it if snapping does nothing.
6. Choose **New Holder**. Leave edit mode. Drag a window until most of it sits inside the outline, then release. It should snap to the outline, and the menu should show `1 window` for that holder.

Global mouse monitoring and window moving both require Accessibility access. Without it, the mouse-up monitor does not fire.

## Sign and notarize a DMG

Distribution outside the App Store needs a **Developer ID Application** certificate, Hardened Runtime (already enabled), and the sandbox left off. Notarization uses an app-specific password or an App Store Connect API key.

Replace `TEAMID` with your Team ID. `notarytool` stores credentials in the keychain on first use.

```bash
# Archive an unsigned-by-Xcode release, or Product → Archive with Developer ID signing.
xcodebuild -project WindowHolder.xcodeproj -scheme WindowHolder -configuration Release \
  -archivePath build/WindowHolder.xcarchive archive \
  DEVELOPMENT_TEAM=TEAMID CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application"

xcodebuild -exportArchive \
  -archivePath build/WindowHolder.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist export-options.plist
```

`export-options.plist` should set `method` to `developer-id`, `signingStyle` to `manual`, and `teamID` to your team. The export produces `WindowHolder.app`.

Sign the app (if the export did not) and a compressed disk image, then notarize and staple:

```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --entitlements WindowHolder/WindowHolder.entitlements \
  "build/export/WindowHolder.app"

codesign --verify --strict --verbose=2 "build/export/WindowHolder.app"

mkdir -p build/dmg
cp -R "build/export/WindowHolder.app" build/dmg/
hdiutil create -volname WindowHolder -srcfolder build/dmg -ov -format UDZO build/WindowHolder.dmg

codesign --force --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  build/WindowHolder.dmg

xcrun notarytool store-credentials "windowholder-notary" \
  --apple-id "you@example.com" --team-id TEAMID --password "app-specific-password"

xcrun notarytool submit build/WindowHolder.dmg \
  --keychain-profile "windowholder-notary" --wait

xcrun stapler staple build/WindowHolder.dmg
xcrun stapler validate build/WindowHolder.dmg
spctl --assess --type open --context context:primary-signature -v build/WindowHolder.dmg
```

If notarization fails, inspect the log:

```bash
xcrun notarytool log <submission-id> --keychain-profile "windowholder-notary"
```

The ticket is stapled to the DMG so Gatekeeper accepts it offline. The app inside must already be signed with Hardened Runtime and a Developer ID certificate.

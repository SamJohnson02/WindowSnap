# WindowHolder

WindowHolder is a Mac app that keeps other apps’ windows together inside an orange outline. Drop a window onto the outline and it stays where you put it. A small pair of buttons at the top-left of the outline minimizes or closes every window locked in that holder.

The app has a normal Dock icon. Click that icon to bring a minimized holder back.

## How to use

Click the WindowHolder icon in the Dock. A holder outline fills the usable area of the screen under the pointer. The menu bar and Dock stay clear.

While WindowHolder is the front app, two menus appear at the top of the screen:

| Menu | Item | Shortcut | What it does |
| --- | --- | --- | --- |
| WindowHolder | Show Holder | | Brings the holder forward, or restores it after minimize |
| WindowHolder | Quit WindowHolder | ⌘Q | Quits the app |
| Holder | New Holder | ⌘N | Adds another outline on the screen under the pointer |
| Holder | Edit Holders | ⌘E | Lets you move and resize the outline. Choose it again (Done Editing) or press Escape to finish |
| Holder | Delete Selected Holder | | Removes the outline you last clicked, while editing |

### Snap a window

1. Leave edit mode so the outline is just a border.
2. Drag a window from another app over the outline and release it.
3. It locks in if more than half of the window is inside the holder, or if the window covers more than half of the holder.
4. The window keeps the size and position you dropped. Drag it again to move or resize it inside the holder.

A click that does not move the window does not snap it. Clicks pass through the orange outline, so the windows inside stay usable. If several holders overlap the same drop, the one with the most overlap wins.

### The buttons

A small control sits at the top-left of each holder. It only covers the two icons.

- **X** (left) closes every window locked in that holder and clears the group.
- **−** (right of the X) minimizes those windows together and hides the holder.

Click the Dock icon, or choose **Show Holder**, to bring them back. They return together in the same places and at the same sizes.

### Move or resize a holder

Choose **Edit Holders** (⌘E). Drag inside the outline to move it. Drag an edge or corner to resize it. The smallest size is about 280×180 points. Press Escape, or choose **Done Editing**, when you are finished.

**Delete Selected Holder** removes the outline you last clicked. It does not close the windows that were inside it.

## First launch

macOS must allow WindowHolder to control other apps. The first time you run it, allow it under **System Settings → Privacy & Security → Accessibility**. If snapping does nothing after you allow it, quit WindowHolder and open it again. The grant applies to the next launch.

If the Holder menu still shows **Reopen to Apply Access**, choose that item, or choose **Open Accessibility Settings…** and turn WindowHolder on.

## Requirements

- macOS 13 or later
- Xcode 15 or later, if you are building it yourself

## Build and run

1. Open `WindowHolder.xcodeproj`.
2. Choose the **WindowHolder** scheme and the **My Mac** destination.
3. Press Run.

Debug builds are signed with a local **WindowHolder Dev** certificate so the Accessibility permission can stick between runs on this Mac. Leave that signing setup as it is. Switching the target to “Sign to Run Locally” makes macOS treat every Run as a different app and ask for Accessibility again.

After a Run, you can keep the app like any other download: in Xcode choose **Product → Show Build Folder in Finder**, drag `WindowHolder.app` into **Applications**, and open it from there. Right-click the Dock icon and choose **Options → Keep in Dock**.

App Sandbox is off. Accessibility control of other apps does not work inside the sandbox. Leave `com.apple.security.app-sandbox` false in `WindowHolder/WindowHolder.entitlements`.

## Share a download

A copy you send to someone else needs an Apple **Developer ID Application** certificate and notarization. The local WindowHolder Dev certificate cannot be notarized. Hardened Runtime is on for Release builds. Keep the sandbox off.

Replace `TEAMID` with your Team ID. `notarytool` stores credentials in the keychain on first use.

```bash
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

The ticket is stapled to the DMG so Gatekeeper can accept it offline. The app inside must already be signed with Hardened Runtime and a Developer ID certificate.

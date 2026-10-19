# WindowHolder

WindowHolder keeps other apps’ windows together inside an orange outline on your Mac. Drop a window on the outline and it stays where you put it.

Other people do not need Xcode. They open `WindowHolder.app` from the Dock, the same way they open any other Mac app. Xcode is only for building the app from this project.

## How to use

Open WindowHolder. An orange outline fills the screen, leaving the menu bar and Dock clear.

Drag a window onto the outline and let go. It locks in when most of the window is inside the outline, or when the window covers most of the outline. It keeps the size and position you dropped. Drag it again to rearrange it.

Two buttons sit at the top-left of the outline:

- **X** closes every window locked in that holder.
- **−** minimizes those windows together and hides the holder.

Click the WindowHolder icon in the Dock to bring them back in the same places and sizes.

With WindowHolder in front, the **Holder** menu at the top of the screen has:

- **New Holder** (⌘N) adds another outline.
- **Edit Holders** (⌘E) lets you drag the outline to move it, or drag an edge to resize it. Press Escape when you are done.
- **Delete Selected Holder** removes the outline you last clicked.

The first time you open it, allow WindowHolder in **System Settings → Privacy & Security → Accessibility**. Quit and open it again if windows do not snap.

## For someone else

Send them a built `WindowHolder.app`, or a disk image that contains it. They move it to Applications and open it. They never open this Xcode project.

macOS blocks an app downloaded from the internet unless it is signed with an Apple Developer ID and notarized. The certificate used for local Xcode runs cannot be shared that way. An Apple Developer account is required before other people can download and open it normally.

## Build it yourself

You need macOS 13 or later and Xcode 15 or later.

1. Open `WindowHolder.xcodeproj`.
2. Choose the **WindowHolder** scheme and **My Mac**.
3. Press Run.

To keep that build like a normal app, choose **Product → Show Build Folder in Finder** and drag `WindowHolder.app` into Applications.

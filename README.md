# WindowSnap

<img src="WindowSnap/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="WindowSnap icon">

WindowSnap is a Mac app that groups windows from other apps into a holder. A holder is an orange outline on the screen. You drag windows onto it and arrange them yourself: two stacked on the left, one on the right, or any other layout. Each window stays the size and in the spot where you dropped it.

Once a window is in the holder, it is locked to that group. You still click and type in those windows as usual. The outline does not get in the way.

The two buttons at the top-left act on every window in that holder at once:

- **−** minimizes the whole group together and hides the outline.
- **X** closes the whole group.

Click the WindowSnap icon in the Dock to bring a minimized group back. The windows return together, in the same places and at the same sizes.

You can add more holders, and you can drag the outline to another part of the screen. A holder stays available on every desktop, including over a full-screen app.

There is no installer on this page yet. To use the app, you build it once in Xcode, then open it like any other Mac app.

## How to install

You need a Mac on macOS 13 or later.

1. Install **Xcode** from the Mac App Store. Open Xcode once. If it asks to install extra components, click **Install** and wait for that to finish.
2. Open [github.com/SamJohnson02/WindowSnap](https://github.com/SamJohnson02/WindowSnap).
3. Click the green **Code** button, then **Download ZIP**.
4. In **Downloads**, double-click the zip file. A folder named `WindowSnap-main` opens.
5. Double-click **WindowSnap.xcodeproj**. Xcode opens.
6. The project is signed for one specific Mac, so a new computer has to change two settings before it will run:
   - In the left sidebar, click the blue **WindowSnap** project icon.
   - Under **TARGETS**, click **WindowSnap**.
   - Open the **Build Settings** tab.
   - In the search box, type `code sign`.
   - Set **Code Signing Identity** to **Sign to Run Locally**.
   - Delete the text in **Other Code Signing Flags**.
7. At the top of the Xcode window, set the scheme to **WindowSnap** and the destination to **My Mac**.
8. Click the **Play** button. The app builds and an orange outline appears.
9. macOS asks for permission. Turn WindowSnap on under **System Settings → Privacy & Security → Accessibility**.
10. Quit WindowSnap, then click **Play** again. WindowSnap works on this second launch.
11. To keep the app after you close Xcode: in the Xcode menu bar choose **Product → Show Build Folder in Finder**. Drag **WindowSnap.app** into **Applications**. Open it from there next time. Right-click the Dock icon and choose **Options → Keep in Dock** if you want it to stay.

## How to use

Open WindowSnap. An orange outline fills the screen, leaving the menu bar and Dock clear.

Drag a window onto the outline and let go. It locks in when most of the window is inside the outline, or when the window covers most of the outline. It keeps the size and position you dropped. Drag it again to rearrange it.

Two buttons sit at the top-left of the outline:

- **X** closes every window locked in that holder.
- **−** minimizes those windows together and hides the holder.

Click the WindowSnap icon in the Dock to bring them back in the same places and sizes.

With WindowSnap in front, the **Holder** menu at the top of the screen has:

- **New Holder** (⌘N) adds another outline.
- **Edit Holders** (⌘E) lets you drag the outline to move it, or drag an edge to resize it. Press Escape when you are done.
- **Delete Selected Holder** removes the outline you last clicked.

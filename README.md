# WindowHolder

WindowHolder keeps other apps’ windows together inside an orange outline on your Mac. Drop a window on the outline and it stays where you put it.

There is no installer on this page yet. To use the app, you build it once in Xcode, then open it like any other Mac app.

## How to install

You need a Mac on macOS 13 or later.

1. Install **Xcode** from the Mac App Store. Open Xcode once. If it asks to install extra components, click **Install** and wait for that to finish.
2. Open [github.com/SamJohnson02/WindowSnap](https://github.com/SamJohnson02/WindowSnap).
3. Click the green **Code** button, then **Download ZIP**.
4. In **Downloads**, double-click the zip file. A folder named `WindowSnap-main` opens.
5. Double-click **WindowHolder.xcodeproj**. Xcode opens.
6. The project is signed for one specific Mac, so a new computer has to change two settings before it will run:
   - In the left sidebar, click the blue **WindowHolder** project icon.
   - Under **TARGETS**, click **WindowHolder**.
   - Open the **Build Settings** tab.
   - In the search box, type `code sign`.
   - Set **Code Signing Identity** to **Sign to Run Locally**.
   - Delete the text in **Other Code Signing Flags**.
7. At the top of the Xcode window, set the scheme to **WindowHolder** and the destination to **My Mac**.
8. Click the **Play** button. The app builds and an orange outline appears.
9. macOS asks for permission. Turn WindowHolder on under **System Settings → Privacy & Security → Accessibility**.
10. Quit WindowHolder, then click **Play** again. Snapping works on this second launch.
11. To keep the app after you close Xcode: in the Xcode menu bar choose **Product → Show Build Folder in Finder**. Drag **WindowHolder.app** into **Applications**. Open it from there next time. Right-click the Dock icon and choose **Options → Keep in Dock** if you want it to stay.

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

# Meimei Notes

Meimei Notes is a native macOS menu-bar app with sticky notes and a countdown in one floating panel. It runs on macOS 14 or later.

## Install and open

1. Double-click **Install MeimeiNotes.pkg** in the `build` folder and follow the macOS Installer. It puts **MeimeiNotes.app** in Applications.
2. Press **⌘Space**, type **meimeinotes**, and press **Return** to open the panel.

If you downloaded a disk image, open it and drag **MeimeiNotes** onto **Applications** before launching it.

Pause briefly with your pointer in the bottom-left corner of a display to bring the panel back. Move onto the panel to keep it open, then move away to dismiss it. **⌘Space** and **Open Notes** in the menu bar also bring it back. You can close it with **Esc** or **×**.

In **Settings → General**, select any corner or choose **Custom spot** and click the display preview to place the trigger. The chosen position applies to each connected display. You can turn the pointer trigger off and use the menu bar to open the panel.

## Notes and timer

- Write in the note area. Use **+** for a new note and click the magnifying glass next to the note title to search titles and text or switch notes. Pin a note to keep it at the top of the list. The app saves edits locally as you type.
- Choose **Export Notes…** from the panel or the menu bar to save a JSON backup with all notes, pins, and the selected note.
- Pick a timer preset or use **Custom…** to set a duration from 1 second to 99 minutes and 59 seconds. Start, pause, resume, or reset the countdown from the panel.
- The timer keeps running when you close the panel, with the remaining time shown in the menu bar. Allow notifications when macOS asks on the first countdown. The system can deliver the countdown alert with the panel closed or after your Mac wakes. Change notifications and the app’s chime in **Settings → General**.

## Cat mode

Cat mode starts off. Turn it on in **Settings → Cat Mode** to put a full-width cat portrait at the top of your note. Choose **Choose Cat Image…** to replace the starter cat with your own photo or transparent PNG. Meimei Notes can remove a photo’s background on your Mac and keeps a full copy of the photo so you can switch between the cutout and the whole image. Use **Use Starter Cat** to switch back.

The bundled starter cat is a transparent PNG generated with the built-in ImageGen tool and saved at [`App/Resources/StarterCat.png`](App/Resources/StarterCat.png).

> A photorealistic cutout of one real-looking orange tabby kitten with a cream chest, in a compact loaf pose with its front paws visible and amber eyes looking at the camera. Eye-level pet photography, soft window light, natural anatomy and fine fur. Frame the complete kitten tightly in a 3:2 landscape composition. True transparent background with clean fur edges. No floor, scenery, props, outline, cast shadow or text.

## Build from source

With Apple’s Command Line Tools or Xcode installed, run this from the project folder.

```sh
./scripts/build-installer.sh
```

The script builds `build/Meimei Notes.app` and `build/Install MeimeiNotes.pkg` for your Mac’s architecture. To build the app bundle on its own, use `./scripts/build-app.sh`.

Run `./scripts/build-dmg.sh` to build a drag-to-Applications disk image in `build`.

## Sign and notarize a release

Use Developer ID Application and Developer ID Installer identities installed in Keychain and a profile created with `xcrun notarytool store-credentials`. The release build signs the app with Hardened Runtime, signs the installer, submits it to Apple, and validates the stapled ticket before producing `build/Install MeimeiNotes (Release).pkg`.

```sh
MEIMEINOTES_APP_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MEIMEINOTES_INSTALLER_SIGN_IDENTITY='Developer ID Installer: Your Name (TEAMID)' \
MEIMEINOTES_NOTARY_PROFILE='meimeinotes-notary' \
./scripts/build-installer.sh --release
```

# Meimei Notes

Meimei Notes is a native macOS menu-bar app with sticky notes and a countdown in one floating panel. It runs on macOS 14 or later.

## Install and open

1. Double-click **Install MeimeiNotes.pkg** in the `build` folder and follow the macOS Installer. It puts **MeimeiNotes.app** in Applications.
2. Press **⌘Space**, type **meimeinotes**, and press **Return** to open the panel.

Pause briefly with your pointer in the bottom-left corner of a display to bring the panel back. You can also choose **Open Notes** from the Meimei Notes icon in the menu bar. Close the panel with **×** or press **Esc** while it has keyboard focus.

In **Settings → General**, select any corner or choose **Custom spot** and click the display preview to place the trigger. The chosen position applies to each connected display. You can turn the pointer trigger off and use the menu bar to open the panel.

## Notes and timer

- Write in the note area. Use **+** for a new note and the note title menu to switch between saved notes. The app saves your edits locally as you type.
- Pick a timer preset or use **Custom…** to set a duration from 1 second to 99 minutes and 59 seconds. Start, pause, resume, or reset the countdown from the panel.
- The timer keeps running when you close the panel, with the remaining time shown in the menu bar. The app plays a sound when the timer ends while the app is running. You can mute it in **Settings → General**.

## Cat mode

Cat mode starts off. Turn it on in **Settings → Cat Mode** to give the panel a warm theme and a cat beside the timer. To use your own cat, choose an image there. Meimei Notes can remove the background from a photo on your Mac or use a transparent PNG. Your original file stays on disk, and you can switch back to the starter cat in Settings.

The bundled starter cat is a transparent PNG generated with the built-in ImageGen tool and saved at [`App/Resources/StarterCat.png`](App/Resources/StarterCat.png).

> A photorealistic cutout of one real-looking orange tabby kitten with a cream chest, in a compact loaf pose with its front paws visible and amber eyes looking at the camera. Eye-level pet photography, soft window light, natural anatomy and fine fur. Frame the complete kitten tightly in a 3:2 landscape composition. True transparent background with clean fur edges. No floor, scenery, props, outline, cast shadow or text.

## Build from source

With Apple’s Command Line Tools or Xcode installed, run this from the project folder.

```sh
./scripts/build-installer.sh
```

The script builds `build/Meimei Notes.app` and `build/Install MeimeiNotes.pkg` for your Mac’s architecture. To build the app bundle on its own, use `./scripts/build-app.sh`.

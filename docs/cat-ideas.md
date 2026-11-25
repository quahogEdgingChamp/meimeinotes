# Cat mode ideas

Cat mode shows a cat portrait at the top of the note. These ideas would give the cat a job in the app instead of only decorating it. None are built yet.

Most of them use the cutout that Cat Mode already makes when it removes a photo's background. A transparent cat can move around, peek out of things, and become an icon.

## Recommended first

Start with **1. The cat reacts to the clock** and **2. The cat peeks out of the hot zone**. They tie the cat to the two things the app does, timing and opening from a corner, and the peek also shows the hot zone has fired. **5. Colors from your cat** is a small extra.

## Ideas

### 1. The cat reacts to the clock

- Sleeps when nothing is running: the portrait dims and a small "Zzz" floats up.
- Sits up while the timer or stopwatch is running.
- Hops and shows a "Time's up!" speech bubble when the countdown ends, alongside the chime and notification.

How: drive the states from `FocusTimer.phase` and `Stopwatch.phase` in `CatNoteHeader`, using SwiftUI saturation, opacity, and spring offsets plus an overlaid bubble. Use a still version when Reduce Motion is on.

### 2. The cat peeks out of the hot zone

When the pointer reaches the trigger corner, the cat slides in from the screen edge just before the panel opens. It gives instant feedback that the corner worked.

How: a small borderless, transparent window at the trigger point animates the cutout during the 0.16 s dwell in `HotZoneMonitor`. Only offer it when the image has a transparent background.

### 3. Pet the cat

Click the portrait for a purr and a few hearts. Double-click to start or pause the selected clock.

How: the portrait currently ignores clicks (`allowsHitTesting(false)`), so it would need tap gestures and a bundled purr sound with a setting to turn it off.

### 4. Your cat in the menu bar

Replace the note icon in the menu bar with a small outline of your cat, next to the time.

How: build a template image from the cutout's alpha mask at menu bar size and use it for the status item's image.

### 5. Colors from your cat

Take the panel's accent and background colors from the photo, so an orange tabby gives a warm theme and a grey cat a cool one.

How: average or cluster the colors of the cutout's opaque pixels with Core Image, then derive `Palette` colors and check text contrast in light and dark mode.

### 6. The cat walks across the screen when the timer ends

The cutout strolls along the bottom of the screen like a real cat interrupting you. Click it to send it away. This should be optional and off by default.

How: a click-through, borderless window above the Dock animates the cutout across the screen. Add a switch in **Settings → Cat Mode** and skip the walk when Reduce Motion is on.

### 7. Focus pet

Each finished countdown gives the cat a treat. The cat shows a streak and how long it has kept you company this week.

How: count finished countdowns per day in `UserDefaults` and show the totals in **Settings → Cat Mode** or as a small badge on the portrait.

### 8. A cat for each note

Each note can have its own cat or photo as a cover, like a page cover.

How: give `Note` an optional image reference and keep the images in the app's Application Support folder, like the current custom cat.

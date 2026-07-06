# Switchy

Native macOS Window Switcher — window-based switching similar to Windows `Alt+Tab`, featuring a live preview overlay, MRU (Most Recently Used) sorting, and support for minimized windows.

## Requirements

* macOS 14 (Sonoma) or newer
* Xcode (tested with Xcode 26)

## Build & Run

```bash
# One-time: Accept the Xcode license (if not already done)
sudo xcodebuild -license accept

# Build
xcodebuild -project Switchy.xcodeproj -scheme Switchy -configuration Debug \
  LD=clang LDPLUSPLUS=clang++ build

```

Or simply open `Switchy.xcodeproj` in Xcode and run it with ⌘R.

> **Note (nix environment):** If a nix-shell is active, it often exports `LD=ld`/`CC`/`CXX`. `LD=ld` overrides Xcode's linker *driver* (which must be `clang`) and leads to `ld: unknown options: -Xlinker …`. Therefore, explicitly set `LD=clang LDPLUSPLUS=clang++` during CLI builds (as shown above). This issue does not occur in Xcode.app.

> The project uses a *File-System-synchronized Group*: new files added to the `Switchy/` folder are automatically included in the target without having to manually edit `project.pbxproj`.

## Permissions (Required)

On the first launch, the app will request the necessary permissions and redirect you to the System Settings. Both must be granted, and the app must be restarted afterward:

1. **Accessibility** — for the system-wide hotkey (event tap) and for focusing/unminimizing third-party windows.
2. **Screen Recording** — for live previews in the overlay.

Path: *System Settings → Privacy & Security → Accessibility* and *Screen Recording*.

## Controls

* **Hold `⌥` + `Tab**` → Global overlay; the second window (MRU) is preselected.
* **Hold `⌥` + ``**` → App-specific switcher: switches only between windows of the active app.
* **Pressing the hotkey key again** → moves one position forward (with wrap-around).
* **Backward:** While holding the modifier, tap the reverse key (default: **left `⇧**`, configurable) — moves the selection back one step without having to press Tab again. The classic **`⇧` + hotkey key** shortcut also continues to work.
* **Release `⌥**` → Focus the selection (unminimizes if needed, changes the Space if necessary).
* **`Esc`** → Close the overlay without switching.
* **Alternatively:** Hover over an item with the mouse (to select) and click (to confirm).

Both hotkeys are fully customizable in the settings; the values above are the defaults.

The app runs as a menu bar agent (no Dock icon). Accessible via the menu bar icon: *Settings…* and *Quit*.

## Settings

The settings window (Menu → *Settings…*) offers:

* **Keyboard Shortcuts:** Shortcut recorders for the global and app-specific switchers, as well as the reverse key (supports single keys, including pure modifiers like the left `⇧`).
* **Window Behavior:** "Include minimized windows" and "Show windows from all screens/Spaces".
* **Launch:** "Launch at login" (via `SMAppService`).

The configuration is persisted in `UserDefaults`; hotkey changes take effect immediately. *Launch at login* works most reliably when the app is placed in a permanent location (e.g., `/Applications`).

## Localization

The interface is localized using a **String Catalog** (`Switchy/Localizable.xcstrings`, permission texts in `Switchy/InfoPlist.xcstrings`). The development/source language is English (`en`); it also includes German (`de`), French (`fr`), Italian (`it`), Spanish (`es`), Hindi (`hi`), and Simplified Chinese (`zh-Hans`). Unsupported system languages fall back to English.

The app follows the system language. To test a specific language without changing the system-wide language:

```bash
open -n "…/Switchy.app" --args -AppleLanguages '(fr)'

```

Simply write new strings in the code as English literals (`Text("…")` or `String(localized: "…")`); the catalog uses the English source text as the lookup key.

## License

Switchy is licensed under the **GNU Lesser General Public License v3.0 (LGPLv3)** —
see [LICENSE.md](LICENSE.md).

Copyright (c) 2026 Jan Gehring &lt;jan@dunkel.tech&gt;

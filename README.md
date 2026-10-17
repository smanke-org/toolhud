# ToolHUD

ToolHUD puts the features of your favorite apps one gesture away. Press a shortcut or click
the mouse in any app, and a ring of buttons opens around the pointer. Click a button and it
runs: capture text with TextLens, turn on ClickLens's spotlight, open PasteLens's Quick
Paste, or press any key combination in any app.

## Download

**[⬇ Download ToolHUD.dmg](https://github.com/smanke-org/ToolHUD/releases/latest/download/ToolHUD.dmg)**

1. Open the disk image and drag **ToolHUD** to **Applications**.
2. Open ToolHUD. Its icon appears in the menu bar.
3. Allow **Accessibility** when asked (System Settings › Privacy & Security › Accessibility).
   The mouse triggers and keystroke buttons need it. The keyboard shortcut and lens actions
   work without it.

Requires macOS 26 or later.

## Use it

| Gesture | What it does |
|---|---|
| ⌃⌥⌘Space | Open the HUD at the pointer, then click a button. Press the shortcut again to close it. |
| ⌥ + right-click | Open the HUD from the mouse, in any app. |
| 1–9, 0 | Run button 1–10 while the HUD is open. |
| ← → ↑ ↓, Tab | Move between buttons; Return runs the lit one. |
| Esc | Close the HUD. |
| ⚙ or , | Open Settings. Every look has a small gear; click it, or press comma. |

A button runs only when you click right on it (a few points' margin forgives a near miss)
or press its number. Letting go of the shortcut or the mouse button never runs anything, so
the HUD stays open until you choose.

The shortcut and the mouse trigger can be changed in Settings › Triggers. The mouse can open the HUD with ⌥ + right-click, by holding the right button (a quick
right-click still opens the app's own menu), with the middle button, or with either side button.

## Buttons

Settings › Buttons holds 2 to 12 buttons. Each has a name, an SF Symbol, a color (or its
app's color) and one of two actions, chosen per button:

- **Lens action**: asks one of our apps to run a feature directly, through its URL scheme
  (`textlens://capture`, `pastelens://quickpaste`). It keeps working if you change that app's
  shortcuts. ToolHUD lists the installed lens apps and their features by name. Until an app
  supports lens actions, ToolHUD presses the feature's default shortcut instead. An app that
  isn't installed links to its page on stevemanke.com.
- **Keystroke**: presses any key combination, either in the app you were using (the HUD never
  takes focus) or in an app you choose, which ToolHUD brings forward first. Turn on the
  modifiers to hold (⌘ ⌥ ⌃ ⇧) and type the key, or several keys to press one after another
  with the same modifiers (⌘K then ⌘S). Return, Tab, the arrows, F-keys and the like are in
  the Special Keys menu.

Rings can be exported to a `.toolhudring` file and imported again, to keep or to share.

### For our other apps

Any app can offer lens actions by registering a URL scheme and listing its features in its
Info.plist. ToolHUD then shows them without an update of its own:

```xml
<key>ToolHUDActions</key>
<array>
    <dict>
        <key>id</key><string>capture</string>        <!-- runs scheme://capture -->
        <key>title</key><string>Capture text</string>
        <key>shortTitle</key><string>Capture</string> <!-- optional: the button's name -->
        <key>symbol</key><string>text.viewfinder</string>
        <key>activates</key><false/>                  <!-- optional: bring the app forward -->
    </dict>
</array>
```

ToolHUD adds `?source=toolhud` to every URL it opens.

## Looks

Settings › Appearance offers ten visualizations, each drawn live in Settings:

- **Rings**: Halo (translucent slices), Orbit (round buttons that spring out), Dial (a rotary
  bezel), Stargate (the chevrons are the buttons, and the gate opens when one locks), Red Alert
  (crimson blades with hazard stripes), Constellation (stars joined by lines), Glass Pills
  (labeled pills) and Planetary (planets that stop drifting when you aim).
- **Button hubs**: Command Deck (a panel of keycaps) and Hive (honeycomb cells).

Opacity, size (small, medium, large), where it opens (pointer or screen center), a sound and a
trackpad haptic are adjustable.

## Sync

With "Sync settings with your other Macs" on (Settings › General), your buttons, look,
shortcut and triggers follow you to every Mac signed in to the same iCloud account. They go
through iCloud Drive, end-to-end encrypted: everything is sealed with AES-256-GCM on your Mac
under a random key, and that key is stored in iCloud only wrapped by your sync passphrase
(PBKDF2-SHA256, 600,000 rounds). The passphrase never leaves your Macs, so neither Apple nor
the developer can read your settings.

## Privacy

ToolHUD has no account, analytics or tracking. The only connection it makes on its own is to
GitHub, to check for updates. Accessibility access is used only to watch the mouse button you
chose as a trigger and to press the keys your buttons send.

## Updates

ToolHUD checks for new versions once a day, or as often as you choose in Settings (a number of hours, days, weeks or months). In Settings › General you choose whether it
installs them automatically when you're not using it, asks first, or doesn't check.

## Automation

`toolhud://show` opens the HUD and `toolhud://settings` opens Settings.

## Build from source

```bash
Tools/make_icns.sh   # once: draws the icon into Resources/AppIcon.icns
./build_app.sh   # universal binary, Developer ID signed
./install.sh     # copies to /Applications in place and launches
swift test       # ToolHUDKit unit tests
./release.sh 1.0.1
```

The disk image's window layout ships as `Resources/dmg/DS_Store`. Capture it once with
`Tools/capture_dmg_layout.sh .build/app/ToolHUD.app ToolHUD Resources/dmg/DS_Store`.

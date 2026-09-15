# Are.na Widget

A macOS widget that shows recent blocks from an Are.na channel. Images fill a
grid of tiles, text blocks are drawn as text. Clicking a block opens it on are.na.

- `ArenaWidget/`: the containing app. One window with setup instructions. It
  exists because macOS widgets have to ship inside an app, and it forwards
  widget clicks to the browser.
- `ArenaWidgetExtension/`: the WidgetKit extension (App Intent configuration).
- `Packages/ArenaKit/`: shared Swift package with the Are.na API client, models,
  image downsampling, and the on-disk cache.

## Requirements

- Apple Silicon Mac, macOS 26 or later
- Xcode 26 or later (built with Xcode 26.6 and the macOS 26.5 SDK)
- No paid developer account. The project signs with "Sign to Run Locally".

## Build

Open `ArenaWidget.xcodeproj`, pick the **ArenaWidget** scheme, and build
(⌘B). Signing is already set to Sign to Run Locally, so you don't need to
select a team.

From the command line:

```sh
xcodebuild -project ArenaWidget.xcodeproj -scheme ArenaWidget \
  -configuration Release -derivedDataPath build/DerivedData build
```

If you'd rather sign with your personal team, set it under Signing &
Capabilities for both targets. Don't add the App Groups capability: a free
account can't issue the provisioning profile it needs, and the build fails.

## Install

The widget won't appear in the gallery while the app only lives in
DerivedData. Copy it to `/Applications` and launch it once:

```sh
ditto build/DerivedData/Build/Products/Release/ArenaWidget.app /Applications/ArenaWidget.app
open /Applications/ArenaWidget.app
```

(When building from Xcode, use Product → Show Build Folder in Finder, then
copy `Products/Debug/ArenaWidget.app`.)

After a rebuild, copy the app again. If the gallery keeps showing an old
version, run `killall chronod NotificationCenter`.

## Add the widget

1. Right-click the desktop and choose **Edit Widgets**.
2. Search for **Are.na**, pick a size, and drag it onto the desktop or into
   Notification Center.
3. Right-click the widget and choose **Edit "Are.na Channel"**. Paste a channel
   slug (the part after the username, e.g. `inspo-syd5sijpqmk` in
   `are.na/dante-smith/inspo-syd5sijpqmk`) or the whole channel URL.
   **Show Titles** adds each block's title along the bottom of its tile.

A new widget shows `inspo-syd5sijpqmk` until you pick another channel.

Sizes: small shows 1 block, medium 2, large 4, extra large 6. Tiles fill the
widget; to change the counts, edit `GridSpec.init(_:)`.

Every 3 minutes the widget shows a new random selection, working through a
shuffled order of the whole channel so every block comes up before any repeat.
Once an hour it lists the channel and downloads only the images for that hour.
They're kept in memory and dropped when the hour is up; nothing is saved to
disk. New blocks join the rotation at the next hourly refresh. Very large
channels are capped at their newest 1,000 blocks. If Are.na can't be reached,
the widget shows empty tiles and tries again every 5 minutes.

Only public channels are supported.

If images look grey on the desktop, that's macOS dimming desktop widgets
while other windows are in front. Change it under System Settings → Desktop &
Dock → Widget style.

## Troubleshooting

Check that the extension is registered:

```sh
pluginkit -m -v -p com.apple.widgetkit-extension | grep -i arena
```

Watch the extension's own log (fetches, tile counts, image bytes, peak memory).
Use the full path: zsh has a builtin called `log` that shadows the system tool.

```sh
/usr/bin/log stream --predicate 'subsystem == "com.dantesmith.ArenaWidget"'
```

## Development

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing targets or
settings, run `xcodegen generate`. The generated project is committed, so you
only need XcodeGen to change it.

ArenaKit has unit tests that run against captured API responses:

```sh
cd Packages/ArenaKit && swift test
```

# Album Widget

A macOS widget that shows the cover of the album I played last. It reads the
same now-playing service as my site, so the desktop and the site always agree.
Clicking it opens the site.

- `AlbumWidget/`: the containing app. It has no windows and no Dock icon. It
  checks the service every 30 seconds and tells the widget to reload when the
  album changes, and it forwards widget clicks to the browser.
- `AlbumWidgetExtension/`: the WidgetKit extension.
- `Shared/`: the service client, compiled into both.

The app exists because macOS decides when a widget may refresh, and left alone
the widget can sit a quarter of an hour behind. With the app running it
follows within about a minute. Without it the widget still refreshes itself
every 15 minutes or so.

## Requirements

- Apple Silicon Mac, macOS 26 or later
- Xcode 26 or later (built with Xcode 27.1)
- No paid developer account. The project signs with "Sign to Run Locally".

## Build

```sh
xcodebuild -project AlbumWidget.xcodeproj -scheme AlbumWidget \
  -configuration Release -derivedDataPath build/DerivedData build
```

Or open `AlbumWidget.xcodeproj`, pick the **AlbumWidget** scheme, and build.

To show your own listening, change `endpoint` and `site` in
`Shared/NowPlaying.swift`. The endpoint has to return JSON with `album`,
`artist`, `track`, and `art` (a cover URL).

## Install

The widget won't appear in the gallery while the app only lives in
DerivedData. Copy it to `/Applications` and launch it once:

```sh
ditto build/DerivedData/Build/Products/Release/AlbumWidget.app /Applications/AlbumWidget.app
open /Applications/AlbumWidget.app
```

The first launch adds the app to your login items and shows a short note.
After that it stays in the background. Open it again to see the note, which
has a Quit button.

After a rebuild, quit the app and copy it again. macOS remembers a widget's
list of sizes per build number, so if you change the sizes, raise
`CURRENT_PROJECT_VERSION` in `project.yml` and run `xcodegen generate`. If the
gallery keeps showing an old version, run `killall chronod NotificationCenter`.

## Add the widget

Right-click the desktop, choose **Edit Widgets**, search for **Last Album**,
and drag a size onto the desktop or into Notification Center.

Small and large are the cover alone. Medium and extra large put the album and
artist beside it.

## Battery

Each check is one small request. Checks stop while the display is asleep and
drop to one every 2 minutes in Low Power Mode. The widget reloads only when the
album changes, not on every track.

## Troubleshooting

Check that the extension is registered:

```sh
pluginkit -m -v -p com.apple.widgetkit-extension | grep -i album
```

Watch the log (album changes from the app, fetch failures from the widget).
Use the full path: zsh has a builtin called `log` that shadows the system tool.

```sh
/usr/bin/log stream --predicate 'subsystem == "com.dantesmith.AlbumWidget"'
```

## Development

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing targets or
settings, run `xcodegen generate`. The generated project is committed, so you
only need XcodeGen to change it.

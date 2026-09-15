# Now Playing

What I'm listening to, in my MacBook's notch.

Spotify scrobbles to Last.fm, my [now-playing Worker](https://now-playing.now-playing.workers.dev/)
turns the latest scrobble into a small JSON answer, and this app asks it every
20 seconds. At rest the notch looks untouched except for a sliver of album art
reaching out of one side. Hover it and it opens into a panel with the art, the
track, the artist and whether it's playing now or when it was last played.
Click the panel to open the track on Last.fm. When nothing has played for 30
minutes it slides back into the notch and disappears.

It's a background agent: no Dock icon, no app switcher entry, just a ♪ in the
menu bar for the preferences and quitting.

## Requirements

- Apple Silicon Mac with macOS 26 or later
- Xcode 26 or later (built with Xcode 26.6)
- No paid developer account. The project signs with "Sign to Run Locally", and
  uses nothing that needs a provisioning profile: no App Groups, no iCloud.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), only if you change
  `project.yml`. The generated project is committed.

## Build and install

Open `NowPlayingNotch.xcodeproj`, choose the **NowPlayingNotch** scheme, and
build (⌘B). Or from the command line:

```sh
xcodebuild -project NowPlayingNotch.xcodeproj -scheme NowPlayingNotch \
  -configuration Release -derivedDataPath build/DerivedData build
```

Then copy it to `/Applications` and open it. Opening at login only works from
there.

```sh
ditto build/DerivedData/Build/Products/Release/NowPlayingNotch.app /Applications/NowPlayingNotch.app
open /Applications/NowPlayingNotch.app
```

After a rebuild, quit the running copy from its ♪ menu and copy it again.

## The service URL

The app asks `https://now-playing.now-playing.workers.dev/` unless told
otherwise. To point it somewhere else, click ♪ in the menu bar, choose
**Preferences…**, paste the URL into **Service URL** and press **Save**. It asks
the service once on the spot and says what came back, or why it couldn't.
**Use Default** puts it back.

The service answers with this shape; `playedAt` can be an ISO 8601 string or
unix seconds:

```json
{ "playing": true, "track": "…", "artist": "…", "album": "…",
  "url": "https://www.last.fm/music/…", "art": "https://…",
  "playedAt": null, "stale": false }
```

## Open at login

In **Preferences…**, turn on **Open at login**. If macOS wants your say-so, the
preferences window tells you and **Open Login Items** takes you to the right
page in System Settings (General → Login Items). Turning it off removes it
again.

## Changing the look

Every size, radius, colour, font, spring and delay is in
[`App/NotchStyle.swift`](App/NotchStyle.swift), grouped by what it affects: the
resting wing, the expanded panel, the opening and closing motion, track
changes, the playing bars, the marquee, and the pill used on screens without a
notch. Change a value, rebuild, reinstall.

One rule there isn't about taste: anything that has to read as part of the
hardware notch is true black (`bezel`), never a material. Translucency next to
the physical cutout gives the illusion away.

## How it works

- **Position.** The panel is a borderless, non-activating `NSPanel` above the
  menu bar. The notch is measured, not hardcoded: its height is the screen's
  top safe-area inset, and its width is the gap between the menu bar areas
  either side of it. Re-measured whenever displays change, on wake and on
  unlock. A screen without a notch gets a pill under the menu bar.
- **The panel never resizes.** It's always big enough for the open state, and
  only what's drawn inside it animates. While closed it lets clicks through to
  the menu bar behind it.
- **Hover.** A mouse monitor catches the pointer reaching the notch, since the
  closed panel ignores the mouse; once open, a tracking area sees it leave.
- **Spaces.** The panel lives in a Space of its own above all the others, the
  way the menu bar does, so swiping between Spaces doesn't slide it out from
  under the notch. That uses the window server's private SkyLight API, looked
  up when the app starts. If a future macOS removes it, the app logs it and the
  panel joins every Space instead, sliding along with swipes. It hides while
  the screen is locked.
- **Polling.** Every 20 seconds while the display is on and unlocked; paused
  during sleep, display sleep and lock, with one question straight away on the
  way back. A failed question keeps showing the last good answer.
- **Art** is downloaded off the main thread, decoded at the size it's drawn,
  and cached on disk by URL. The last good answer is kept on disk too, so the
  notch shows it the moment the app starts.

## Files

Everything lives in the app's own container,
`~/Library/Containers/com.dantesmith.NowPlayingNotch/Data/Library/`:
`Caches/Artwork` (album art, the 300 most recently used),
`Application Support/NowPlayingNotch/last-answer.json`, and the preferences.
To uninstall, quit the app, delete it from `/Applications`, and delete that
container folder.

## Troubleshooting

Watch what it's doing: each answer that changes, what's on the notch, art
loading, polling pausing and resuming, and the Space setup.

```sh
/usr/bin/log stream --predicate 'subsystem == "com.dantesmith.NowPlayingNotch"'
```

(The full path matters: zsh has a builtin called `log`.)

## Development

The geometry, the service's answer, the relative times, the marquee's motion
and the caches are in `Packages/NotchKit`, with tests:

```sh
cd Packages/NotchKit && swift test
```

After changing targets or settings in `project.yml`, run `xcodegen generate`.

Not yet tried on real hardware: an external display. The pill it falls back to
there is covered by the geometry tests.

# My MacBook customizations

Things I've built for my Mac.

- [`notch-now-playing/`](notch-now-playing) shows what I'm listening to in the
  MacBook's notch. Spotify scrobbles to Last.fm, a small service of mine turns
  that into JSON, and the app polls it. At rest it's a sliver of album art out
  of the side of the notch; hover it to open, click to go to the track.
- [`arena-widget/`](arena-widget) is a desktop widget that rotates through the
  blocks of an Are.na channel, a new selection every 3 minutes.

Each folder is a complete Xcode project with its own README covering the
build, the install, and the setup. Both build with a free Apple ID ("Sign to
Run Locally") and use nothing that needs a provisioning profile.

The now-playing service the notch app reads isn't in this repo. It's a
separate Cloudflare Worker, and it's where the Last.fm key lives.

Each project keeps its full commit history (added with `git subtree`).

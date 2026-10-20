# Release pictures

Whatever is in this folder is published with the next release and shown in the app's
**Software Update** screen and on the GitHub release page.

* `banner.png` - the hero image (1600x800 works well). Omit it and CI draws one.
* `*.png`, `*.jpg`, `*.webp` - screenshots, up to 8, sorted by file name. Phone screenshots in
  portrait look best.
* `captions.json` (optional) - `{ "equalizer.jpg": "The new equalizer" }`. Without it the file
  name becomes the caption (`home-screen.jpg` -> "Home screen").

Replace these before a release you want to announce; the previous release keeps its own copies.

# Releasing Mine Music (push -> phone)

```
git push  ->  CI (analyze + test)  ->  signed APK  ->  GitHub Release  ->  the app offers it
                                         |                |
                                   build number      notes + banner + screenshots
                                   from the run      + SHA-256 + update.json
```

Every push to `master`/`main` that passes CI becomes a release. The app checks GitHub when it
opens (at most every six hours), tells you once per version, shows the notes and pictures,
downloads the APK, verifies its SHA-256, and hands it to the system installer.

## One-time setup (about two minutes)

Android only installs an update over an app signed with the **same key**. CI therefore needs the
key, as four repository secrets. `tool/release/setup-signing.ps1` does it for you:

```powershell
# Keep updating the copies you already installed from `flutter run` / a local build
# (they are signed with this machine's debug key). No reinstall needed.
pwsh tool/release/setup-signing.ps1 -UseDebugKey

# or: a fresh release key (phones with the old copy must uninstall once, first time only)
pwsh tool/release/setup-signing.ps1 -Generate
```

With the GitHub CLI installed and logged in (`gh auth login`) it uploads the secrets itself;
otherwise it prints what to paste into *Settings > Secrets and variables > Actions*:

| Secret | What |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | the `.jks`, base64 |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

Both APKs carry the same versionCode, so Android treats them as one app. Without the secrets the release job **stops with a clear message** instead of publishing an APK that no
installed copy would accept.

> The workflows live on the default branch. `refactor/liquid-glass` has never been pushed: merge
> or push it to `master` to publish the first OTA build.

## What a release contains

| Asset | Used for |
| --- | --- |
| `MineMusic-<version>-b<build>.apk` | the universal APK (~100 MB; runs on any CPU) |
| `MineMusic-<version>-b<build>-arm64-v8a.apk` | the arm64 APK (about a third of the size); the app picks it on phones that run arm64, which is nearly all of them |
| `...apk.sha256` | checksum (also inside `update.json`) |
| `update.json` | what the app reads: version, notes, images, size, checksum |
| `...-banner.png`, `...-<screenshot>` | shown in the app's update screen and the release page |

### Versions
* `version:` in `pubspec.yaml` is the **name** (`1.1.0`). Bump it when you want a new name.
* The **build number** (Android's versionCode) is `workflow run number + 100`, so it always goes up
  and needs no commit. Tag: `v1.1.0+142`.
* Push a tag `v2.0.0` (or `v2.0.0+500`) to pick the name yourself. `-beta.1` names, or *Run
  workflow > prerelease*, publish on the **beta channel** (marked pre-release; only phones with
  *Get early builds* on see them).
* Put `[skip release]` in a commit message to push without releasing. Markdown-only and `docs/`
  changes never release.

### Release notes
In order of preference:
1. **`release/notes/<version>.md`**, hand written: a `# Title`, one line of summary, then
   `## New` / `## Improved` / `## Fixed` sections with `- bullets`.
2. Otherwise the commits since the last release, turned into plain sentences:
   `feat:` -> New, `fix:` -> Fixed, `perf:`/`refactor:`/`design:`/`ui:` -> Improved;
   `chore`, `docs`, `test`, `ci`, `build` are left out. `;` splits one commit into several lines and
   detail after ` - ` is dropped, so write the headline first:
   `feat(eq): a real equalizer - native effects, 23 presets, per-output profiles`.

### Pictures
* `release/images/banner.png` (1600x800 works well). If absent, CI draws one with the app mark and
  the version.
* `release/images/*.png|jpg|webp` (up to 8, sorted by name) are the screenshots. Optional
  `captions.json`: `{ "equalizer.jpg": "The new equalizer" }`; otherwise the file name is the caption.

## `update.json` (schema 1)

```json
{ "schema": 1, "app": "mine-music", "version": "1.1.0", "build": 142, "tag": "v1.1.0+142",
  "channel": "stable", "publishedAt": "2026-10-20T12:00:00Z", "minSdk": 24,
  "title": "…", "summary": "…", "highlights": ["…"],
  "sections": [{ "title": "New", "icon": "sparkle", "items": ["…"] }],
  "notes": "markdown body", "images": { "banner": "https://…", "gallery": [{ "url": "…", "caption": "…" }] },
  "assets": [{ "name": "…apk", "abi": "universal", "url": "https://…", "size": 62914560, "sha256": "…" }],
  "releaseUrl": "https://github.com/<owner>/<repo>/releases/tag/v1.1.0%2B142" }
```

Without `update.json` the app falls back to the GitHub release body (same layout, parsed) and a
sibling `.sha256` asset.

## In the app

* **Settings > Software update** (a banner appears at the top of Settings when one is waiting):
  morphing *Check / Download / Cancel / Install* button, a progress ring with speed and time left,
  the release notes with banner and screenshots, *Check automatically*, *Get early builds*.
* An **update sheet** opens once per version (never over the player or another screen);
  *Later*, *Details*, *Skip this version*.
* After updating, a **What's new** sheet shows the notes for the version you now run.
* Safety: HTTPS only; size and SHA-256 are checked before the installer is offered; Android itself
  refuses an update signed with a different key or a lower versionCode.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Release job fails at *Require the signing key* | Secrets missing: run `setup-signing.ps1`. |
| Phone says "App not installed" / "signature conflict" | The installed copy is signed with a different key. Use `-UseDebugKey` for copies built locally, or uninstall once. |
| App says up to date after a push | Checks are throttled to 6 h; *Software update > Check for updates* forces one. GitHub's unauthenticated API allows 60 requests/hour per IP. |
| Wrong notes | Add `release/notes/<version>.md`, or reword commits. |
| Banner missing | CI uses ImageMagick; commit `release/images/banner.png` to control it. |
| Roll back | Delete the release on GitHub; `releases/latest` falls back to the previous one. Installed phones keep what they have (Android never downgrades). To supersede a bad build, push a fix: it gets a higher build number. |

## Local release build

`flutter build apk --release` works without secrets (signed with the debug key). To sign locally
with the real key, create `android/key.properties` (gitignored):

```
storeFile=../release.jks
storePassword=…
keyAlias=minemusic
keyPassword=…
```

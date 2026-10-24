# Security policy

## Reporting a vulnerability

Open a [private security advisory](https://github.com/KESPREME/music_streaming_app/security/advisories/new)
or email the maintainer. Please do not open a public issue for anything that could
expose a user's account, listening history or playback tokens.

We aim to acknowledge within 72 hours.

## What is *not* a leak

The repository contains three Google API keys. GitHub's secret scanning flags all of
them, and every one is a public identifier rather than a credential:

| Location | Key | Why it is public |
|---|---|---|
| `lib/services/innertube/innertube_service.dart` | InnerTube WEB key | Ships in every `youtube.com` page and every YouTube client. |
| `lib/services/potoken/po_token_webview.dart` | WEB_REMIX key | Same key the YouTube Music web player uses to run BotGuard. |
| `android/app/google-services.json` | Firebase Android key | Identifying config, shipped inside the APK by design. Access is controlled by Firebase security rules, not by hiding the key. |

None of them grant access to a Google account, and none can be rotated by this
project — they belong to Google. Alerts for these three files can be closed as
"used in tests" / false positive.

The Firebase key should still be **restricted** in the Firebase console (API
restrictions: Android apps, package `com.example.music_streaming_app`, your signing
SHA-1). That is the control that matters; hiding the key is not.

## What *is* a leak

- Cookies, `SAPISID`/`HSID`/`SSID`, `dataSyncId` or any captured `/player` or
  `account_menu` response containing them.
- `key.properties`, keystores, and the CI secrets `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- `--dart-define` values below are *user-supplied and optional*; a real Spotify
  client secret must never be committed:
  `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`.

Captured InnerTube fixtures are welcome in tests only after the visitor data,
account identity and any cookie-derived headers have been stripped.

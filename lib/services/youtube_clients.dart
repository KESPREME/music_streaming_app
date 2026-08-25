/// Credit: Based on yt-dlp YouTube extractor implementation
/// https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py
library;

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Canonical User-Agent strings shared by all services that talk to
/// YouTube-backed endpoints (audio_service, innertube_service,
/// youtube_stream_source, cobalt_service).
const kBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const kAndroidUserAgent =
    'com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip';
/// UA for ANDROID_VR stream URLs — must accompany every request to a
/// VR-resolved googlevideo URL or the CDN answers 403.
const kAndroidVrStreamUserAgent =
    'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; Quest 3 Build/SQ3A.220605.009.A1) gzip';

const kIosUserAgent =
    'com.google.ios.youtube/20.51.39 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)';

const customAndroidVr = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'ANDROID_VR',
      'clientVersion': '1.65.10',
      'deviceModel': 'Quest 3',
      'osVersion': '12L',
      'osName': 'Android',
      'androidSdkVersion': '32',
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
    },
    'contextClientName': 28,
    'requireJsPlayer': false,
  },
}, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

const customAndroidSdkless = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'ANDROID',
      'clientVersion': '20.10.38',
      'userAgent':
          'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
      'osName': 'Android',
      'osVersion': '11',
    },
  },
  'contextClientName': 3,
  'requireJsPlayer': false,
}, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');


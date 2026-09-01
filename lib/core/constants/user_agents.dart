/// Canonical User-Agent constants for stream extraction.
///
/// Single source of truth: audio retry paths and InnerTube clients must use
/// these instead of hardcoding strings (a mismatched UA causes googlevideo
/// 403s because the probe UA is baked into the signed URL).
const String kAndroidVrStreamUserAgent =
    'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; Quest 3 Build/SQ3A.220605.009.A1) gzip';

const String kWebRemixUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

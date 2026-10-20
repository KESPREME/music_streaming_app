// lib/services/update/update_service.dart
//
// The in-app updater's state machine. The UI watches this one ChangeNotifier
// and nothing else; every network, disk and OS call happens behind it.
//
//   idle -> checking -> upToDate
//                    -> available -> downloading -> verifying -> ready
//                                                                  -> installing
//                                                                  -> needsPermission -> (allow, install again)
//   any step -> failed (with a sentence for a person and the step that broke)
//
// Rules this class keeps:
//   * Nothing here throws into the app. Prefs failing, the disk full, GitHub
//     down, a malformed manifest: each becomes a state with a sentence.
//   * A check never costs more than it must: throttled to once per
//     [minCheckInterval], conditional on the stored ETag (a 304 is free), and
//     silent while rate limited.
//   * Never offer an install that cannot work: a release whose `minSdk` is
//     above this phone is reported as "Needs Android X", not offered.
//   * A cached release keeps the UI useful offline - and an offline check that
//     fails keeps the cached update instead of replacing it with an error.
//   * Only a file that passed its checksum is ever handed to the installer.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_platform.dart';
import 'update_downloader.dart';
import 'update_http.dart';
import 'update_json.dart';
import 'update_models.dart';
import 'update_repository.dart';
import 'version_compare.dart';

/// SharedPreferences keys, in one place so a test (or a migration) can find
/// them.
abstract final class UpdatePrefs {
  static const String autoCheck = 'update_auto_check';
  static const String channel = 'update_channel';
  static const String lastCheckMs = 'update_last_check_ms';
  static const String etag = 'update_etag';
  static const String cachedRelease = 'update_cached_release';
  static const String skippedVersion = 'update_skipped_version';
  static const String promptedVersion = 'update_prompted_version';
  static const String lastRunVersion = 'update_last_run_version';

  /// When a rate-limited client may ask again (ms since epoch).
  static const String retryAfterMs = 'update_retry_after_ms';
}

/// "Needs Android 9" - the marketing version for an API level.
String androidVersionName(int sdkInt) => switch (sdkInt) {
      <= 20 => '5',
      21 || 22 => '5.${sdkInt - 21}',
      23 => '6',
      24 => '7.0',
      25 => '7.1',
      26 => '8.0',
      27 => '8.1',
      28 => '9',
      29 => '10',
      30 => '11',
      31 => '12',
      32 => '12L',
      33 => '13',
      34 => '14',
      35 => '15',
      36 => '16',
      _ => '(API $sdkInt)',
    };

class UpdateService extends ChangeNotifier {
  UpdateService({
    UpdateRepository? repository,
    UpdateDownloader? downloader,
    Future<SharedPreferences> Function()? prefs,
    Future<Directory> Function()? updatesDir,
    Future<AppInfo> Function()? appInfo,
    Future<InstallResult> Function(String path)? installer,
    Future<bool> Function()? canInstall,
    DateTime Function()? now,
    this.minCheckInterval = const Duration(hours: 6),
  })  : _repo = repository ?? UpdateRepository(),
        _ownsRepo = repository == null,
        _downloader = downloader ?? UpdateDownloader(),
        _ownsDownloader = downloader == null,
        _prefsFn = prefs ?? SharedPreferences.getInstance,
        _dirFn = updatesDir ?? _defaultUpdatesDir,
        _appInfoFn = appInfo ?? AppPlatform.info,
        _installer = installer ?? AppPlatform.installApk,
        _canInstallFn = canInstall ?? AppPlatform.canInstall,
        _now = now ?? DateTime.now;

  /// How long a successful check suppresses the next automatic one.
  final Duration minCheckInterval;

  final UpdateRepository _repo;
  final bool _ownsRepo;
  final UpdateDownloader _downloader;
  final bool _ownsDownloader;
  final Future<SharedPreferences> Function() _prefsFn;
  final Future<Directory> Function() _dirFn;
  final Future<AppInfo> Function() _appInfoFn;
  final Future<InstallResult> Function(String path) _installer;
  final Future<bool> Function() _canInstallFn;
  final DateTime Function() _now;

  /// The host's `cache/updates` - the only folder the installer accepts.
  static Future<Directory> _defaultUpdatesDir() async {
    final tmp = await getTemporaryDirectory();
    return Directory(joinPath(tmp, 'updates'));
  }

  // -- state ----------------------------------------------------------------

  UpdateState _state = const UpdateState();
  AppInfo _installed = AppInfo.unknown;
  UpdateChannel _channel = UpdateChannel.stable;
  bool _autoCheck = true;
  DateTime? _lastChecked;
  String? _etag;

  /// The newest release the server last described (newer than us or not).
  ReleaseInfo? _cached;
  String? _skippedId;
  String? _promptedId;
  DateTime? _retryAfter;
  ReleaseInfo? _whatsNew;

  bool _initialized = false;
  Future<void>? _initFuture;
  bool _disposed = false;

  SharedPreferences? _prefs;
  Directory? _dir;

  /// The verified file for [_verifiedFor], so a re-check does not re-hash it.
  String? _verifiedPath;
  String? _verifiedFor;

  CancelToken? _token;

  /// Bumped when a result in flight must be discarded (channel changed).
  int _epoch = 0;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastProgressNotifyMs = -1000;

  // -- public read side -----------------------------------------------------

  UpdateState get state => _state;
  UpdateStatus get status => _state.status;
  ReleaseInfo? get release => _state.release;
  double get progress => _state.progress;

  /// What this phone is running. [AppInfo.unknown] until [initialize] finishes.
  AppInfo get installed => _installed;
  DateTime? get lastChecked => _lastChecked;
  UpdateChannel get channel => _channel;
  bool get autoCheck => _autoCheck;
  bool get initialized => _initialized;

  /// Path of the verified APK once [UpdateStatus.ready]; else null.
  String? get downloadedPath =>
      _verifiedFor != null && _verifiedFor == _state.release?.id ? _verifiedPath : null;

  /// A newer, not-skipped release is on offer, or being fetched/installed.
  bool get hasUpdate {
    final r = _state.release;
    if (r == null || _isSkipped(r)) return false;
    return switch (_state.status) {
      UpdateStatus.available ||
      UpdateStatus.downloading ||
      UpdateStatus.verifying ||
      UpdateStatus.ready ||
      UpdateStatus.installing ||
      UpdateStatus.needsPermission ||
      UpdateStatus.failed =>
        true,
      _ => false,
    };
  }

  /// [hasUpdate] and the user has not been told about this version yet.
  bool get shouldPrompt {
    final r = _state.release;
    return r != null && hasUpdate && _promptedId != r.id;
  }

  /// Set when the running version differs from the one the app last recorded
  /// (it was just updated). Notes may be empty until [loadWhatsNewNotes].
  ReleaseInfo? get whatsNew => _whatsNew;

  // -- lifecycle ------------------------------------------------------------

  /// Loads settings and the cached release, cleans the updates folder and
  /// works out [whatsNew]. Idempotent; never throws.
  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    try {
      _prefs = await _guard(_prefsFn);
      _installed = await _guard(_appInfoFn) ?? AppInfo.unknown;
      _dir = await _guard(_dirFn);
      _readSettings();

      final cached = _readCache();
      _cached = cached;

      final running = _runningId;
      final previousRun = _readString(UpdatePrefs.lastRunVersion);

      // "What's new" the first time a new build runs. The cached release is
      // the best source of notes when it is the very build that was installed.
      if (previousRun != null && previousRun != running && _installed.isKnown) {
        _whatsNew = cached != null && _isSameBuild(cached) ? cached : _notesLessRunning();
      }
      await _writeString(UpdatePrefs.lastRunVersion, running);

      if (cached != null && !_isNewer(cached)) {
        // Already installed (or older): the cache has done its job.
        _cached = null;
        await _remove(UpdatePrefs.cachedRelease);
      }

      final offered = _cached;
      await _sweep(keepFor: offered != null && _isNewer(offered) ? offered : null);
      await _applyRelease(offered, initial: true);
    } catch (e) {
      logUpdate('initialize failed: $e');
    } finally {
      _initialized = true;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    if (_ownsRepo) _repo.close();
    if (_ownsDownloader) _downloader.close();
    super.dispose();
  }

  // -- checking -------------------------------------------------------------

  /// Asks GitHub whether there is something newer.
  ///
  /// Without [force] this is a cheap no-op when auto-check is off, when the
  /// last check was under [minCheckInterval] ago, or while GitHub has asked us
  /// to back off. Never throws.
  Future<void> check({bool force = false}) async {
    await initialize();
    if (_disposed) return;
    switch (_state.status) {
      case UpdateStatus.checking ||
            UpdateStatus.downloading ||
            UpdateStatus.verifying ||
            UpdateStatus.installing:
        return;
      default:
        break;
    }

    final now = _now();
    if (!force) {
      if (!_autoCheck) {
        _notify();
        return;
      }
      final until = _retryAfter;
      if (until != null && now.isBefore(until)) {
        _notify();
        return;
      }
      final last = _lastChecked;
      if (last != null) {
        final age = now.difference(last);
        if (!age.isNegative && age < minCheckInterval) {
          _notify();
          return;
        }
      }
    }

    final epoch = _epoch;
    final before = _state;
    _state = before.copyWith(
      status: UpdateStatus.checking,
      error: null,
      failedDuring: null,
    );
    _notify();

    FetchResult result;
    try {
      result = await _repo.fetchLatest(
        channel: _channel,
        abis: _installed.abis,
        etag: _etag,
      );
    } catch (e) {
      logUpdate('repository threw: $e');
      result = const Failed(kUnreachableMessage);
    }
    if (_disposed || epoch != _epoch) return;

    switch (result) {
      case Fetched(:final release, :final etag):
        await _onFetched(release, etag);
      case NotModified():
        _lastChecked = _now();
        await _writeInt(UpdatePrefs.lastCheckMs, _lastChecked!.millisecondsSinceEpoch);
        await _clearBackoff();
        await _applyRelease(_cached);
      case RateLimited(:final retryAt):
        await _onRateLimited(retryAt, before, force: force);
      case Failed(:final message):
        await _onFailed(message);
    }
    if (_disposed || epoch != _epoch) return;
    await _sweep(keepFor: _state.release);
  }

  Future<void> _onFetched(ReleaseInfo? release, String? etag) async {
    _lastChecked = _now();
    _cached = release;
    _etag = etag;
    await _writeInt(UpdatePrefs.lastCheckMs, _lastChecked!.millisecondsSinceEpoch);
    // Cache first, then the ETag: a crash in between leaves a cache without a
    // tag (a full refetch), never a tag without a cache (a 304 with nothing to
    // show).
    if (release != null) {
      await _writeString(UpdatePrefs.cachedRelease, jsonEncode(release.toJson()));
    } else {
      await _remove(UpdatePrefs.cachedRelease);
    }
    if (etag != null && etag.isNotEmpty) {
      await _writeString(UpdatePrefs.etag, etag);
    } else {
      await _remove(UpdatePrefs.etag);
    }
    await _clearBackoff();
    await _applyRelease(release);
  }

  Future<void> _onRateLimited(
    DateTime? retryAt,
    UpdateState before, {
    required bool force,
  }) async {
    final now = _now();
    _retryAfter = retryAt ?? now.add(const Duration(minutes: 15));
    await _writeInt(UpdatePrefs.retryAfterMs, _retryAfter!.millisecondsSinceEpoch);
    if (force && _cached == null) {
      _state = UpdateState(
        status: UpdateStatus.failed,
        error: 'GitHub is limiting requests right now. '
            'Try again ${_waitPhrase(_retryAfter!.difference(now))}.',
        failedDuring: UpdateStatus.checking,
        checkedAt: _lastChecked,
      );
      _notify();
      return;
    }
    // Keep what we had; nothing the user needs to see.
    _state = before;
    _notify();
  }

  Future<void> _onFailed(String message) async {
    final cached = _cached;
    if (cached != null && _classify(cached).release != null) {
      // A refresh failed but an update is already known: keep offering it and
      // just note why the refresh did not happen.
      await _applyRelease(cached, error: message);
      return;
    }
    _state = UpdateState(
      status: UpdateStatus.failed,
      error: message,
      failedDuring: UpdateStatus.checking,
      checkedAt: _lastChecked,
    );
    _notify();
  }

  // -- downloading ----------------------------------------------------------

  /// Downloads the update. Only from [UpdateStatus.available] or from
  /// [UpdateStatus.failed] with a release; otherwise a no-op. A partial file
  /// from an earlier attempt is resumed. Never throws.
  Future<void> download() async {
    if (_disposed) return;
    final r = _state.release;
    final asset = r?.asset;
    final s = _state.status;
    if (r == null || asset == null) return;
    if (s != UpdateStatus.available && s != UpdateStatus.failed) return;
    if (_token != null) return;

    // Choosing to download overrides an earlier "skip this version".
    if (_skippedId == r.id) {
      _skippedId = null;
      await _remove(UpdatePrefs.skippedVersion);
    }

    final token = _token = CancelToken();
    final dir = await _ensureDir();
    if (_disposed) return;
    if (dir == null) {
      _token = null;
      _state = _state.copyWith(
        status: UpdateStatus.failed,
        error: 'There is no room to save the update on this phone.',
        failedDuring: UpdateStatus.downloading,
      );
      _notify();
      return;
    }

    _lastProgressNotifyMs = -1000;
    _state = _state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0,
      receivedBytes: 0,
      totalBytes: asset.size,
      bytesPerSecond: 0,
      etaSeconds: null,
      error: null,
      failedDuring: null,
    );
    _notify();

    DownloadOutcome outcome;
    try {
      outcome = await _downloader.download(
        asset,
        dir: dir,
        onProgress: _onProgress,
        onVerifying: _onVerifying,
        cancel: token,
      );
    } catch (e) {
      logUpdate('downloader threw: $e');
      outcome = DownloadOutcome.failed(kDownloadInterruptedMessage);
    }
    _token = null;
    if (_disposed) return;

    switch (outcome) {
      case DownloadCompleted(:final file):
        _verifiedPath = file.path;
        _verifiedFor = r.id;
        final bytes = asset.size > 0 ? asset.size : await _lengthOf(file);
        if (_disposed) return;
        _state = _state.copyWith(
          status: UpdateStatus.ready,
          progress: 1,
          receivedBytes: bytes,
          totalBytes: bytes,
          bytesPerSecond: 0,
          etaSeconds: null,
          error: null,
          failedDuring: null,
        );
      case DownloadCancelled():
        // cancel() already put the state back; this covers a token cancelled
        // some other way.
        if (_state.status == UpdateStatus.downloading ||
            _state.status == UpdateStatus.verifying) {
          _state = _backToAvailable();
        }
      case DownloadCorrupt():
        _verifiedPath = null;
        _verifiedFor = null;
        _state = _state.copyWith(
          status: UpdateStatus.failed,
          progress: 0,
          receivedBytes: 0,
          bytesPerSecond: 0,
          etaSeconds: null,
          error: kDownloadCorruptMessage,
          failedDuring: UpdateStatus.verifying,
        );
      case DownloadFailed(:final message):
        if (token.isCancelled) {
          // The user cancelled and the dying transfer reported an error on its
          // way out; that is not a failure.
          _state = _backToAvailable();
        } else {
          _state = _state.copyWith(
            status: UpdateStatus.failed,
            bytesPerSecond: 0,
            etaSeconds: null,
            error: message,
            failedDuring: UpdateStatus.downloading,
          );
        }
    }
    _notify();
  }

  /// Stops a running download and returns to [UpdateStatus.available]. The
  /// partial file is kept, so [download] resumes where this stopped.
  void cancel() {
    final t = _token;
    if (t == null) return;
    t.cancel();
    if (_state.status == UpdateStatus.downloading) {
      _state = _backToAvailable();
      _notify();
    }
  }

  UpdateState _backToAvailable() => _state.copyWith(
        status: UpdateStatus.available,
        progress: 0,
        receivedBytes: 0,
        bytesPerSecond: 0,
        etaSeconds: null,
        error: null,
        failedDuring: null,
      );

  void _onProgress(DownloadProgress p) {
    if (_disposed || _state.status != UpdateStatus.downloading) return;
    _state = _state.copyWith(
      progress: p.fraction,
      receivedBytes: p.received,
      totalBytes: p.total,
      bytesPerSecond: p.bytesPerSecond,
      etaSeconds: p.etaSeconds,
    );
    // The state is always current; listeners hear about it ~10 times a second.
    final ms = _clock.elapsedMilliseconds;
    if (ms - _lastProgressNotifyMs >= 100 || p.fraction >= 1) {
      _lastProgressNotifyMs = ms;
      _notify();
    }
  }

  void _onVerifying() {
    if (_disposed || _state.status != UpdateStatus.downloading) return;
    _state = _state.copyWith(
      status: UpdateStatus.verifying,
      progress: 1,
      bytesPerSecond: 0,
      etaSeconds: null,
    );
    _notify();
  }

  // -- installing -----------------------------------------------------------

  /// Hands the verified APK to the system installer.
  ///
  /// [InstallResult.started]: the OS takes over; state stays
  /// [UpdateStatus.installing] until the app is replaced or resumes
  /// ([refreshAfterResume]). [InstallResult.needsPermission]: the user must
  /// allow installs from this app, then call this again. Only valid from
  /// ready / needsPermission (or failed-while-installing); otherwise returns
  /// [InstallResult.unavailable] without touching state.
  Future<InstallResult> install() async {
    if (_disposed) return InstallResult.unavailable;
    final r = _state.release;
    final s = _state.status;
    final allowed = s == UpdateStatus.ready ||
        s == UpdateStatus.needsPermission ||
        (s == UpdateStatus.failed && _state.failedDuring == UpdateStatus.installing);
    final path = r != null && _verifiedFor == r.id ? _verifiedPath : null;
    if (r == null || !allowed || path == null) return InstallResult.unavailable;

    if (!await File(path).exists()) {
      // Swept away (cache cleared by the OS?). Offer the download again.
      _verifiedPath = null;
      _verifiedFor = null;
      if (_disposed) return InstallResult.unavailable;
      _state = _backToAvailable();
      _notify();
      return InstallResult.unavailable;
    }

    _state = _state.copyWith(
      status: UpdateStatus.installing,
      error: null,
      failedDuring: null,
    );
    _notify();

    InstallResult result;
    try {
      result = await _installer(path);
    } catch (e) {
      logUpdate('installer threw: $e');
      result = InstallResult.unavailable;
    }
    if (_disposed) return result;

    switch (result) {
      case InstallResult.started:
        break;
      case InstallResult.needsPermission:
        _state = _state.copyWith(status: UpdateStatus.needsPermission);
        _notify();
      case InstallResult.unavailable:
        _state = _state.copyWith(
          status: UpdateStatus.failed,
          error: 'This phone could not start the installer.',
          failedDuring: UpdateStatus.installing,
        );
        _notify();
    }
    return result;
  }

  /// Call when the app returns to the foreground. If the installer was shown
  /// but this app is still the old one, go back to [UpdateStatus.ready]; if it
  /// is now the new version, clear the update. While "install unknown apps" is
  /// still off, stay in [UpdateStatus.needsPermission].
  Future<void> refreshAfterResume() async {
    await initialize();
    if (_disposed) return;
    final s = _state.status;
    if (s != UpdateStatus.installing && s != UpdateStatus.needsPermission) return;
    final r = _state.release;

    var info = _installed;
    try {
      info = await _appInfoFn();
    } catch (_) {}
    var mayInstall = false;
    try {
      mayInstall = await _canInstallFn();
    } catch (_) {}
    if (_disposed || _state.status != s) return;

    _installed = info;
    if (r != null && !_isNewer(r)) {
      await _clearUpdate();
      return;
    }
    if (s == UpdateStatus.needsPermission && !mayInstall) return;
    _state = _state.copyWith(status: UpdateStatus.ready, error: null, failedDuring: null);
    _notify();
  }

  // -- user choices ---------------------------------------------------------

  /// Hides the prompt for this version until a newer one appears.
  Future<void> skipThisVersion() async {
    await initialize();
    final r = _state.release;
    if (r == null) return;
    _skippedId = r.id;
    _notify();
    await _writeString(UpdatePrefs.skippedVersion, r.id);
  }

  /// Records that the user has been shown this version, so [shouldPrompt]
  /// goes quiet.
  Future<void> markPrompted() async {
    await initialize();
    final r = _state.release;
    if (r == null) return;
    _promptedId = r.id;
    _notify();
    await _writeString(UpdatePrefs.promptedVersion, r.id);
  }

  Future<void> setAutoCheck(bool value) async {
    // Initialise first: a write before the preferences are open would be lost,
    // and initialize() would then overwrite this choice with the stored one.
    await initialize();
    _autoCheck = value;
    _notify();
    await _writeBool(UpdatePrefs.autoCheck, value);
  }

  /// Switches stream. Forgets the cached release and ETag (they described the
  /// other stream) and makes the next [check] run regardless of the throttle.
  Future<void> setChannel(UpdateChannel value) async {
    await initialize();
    if (value == _channel) return;
    _channel = value;
    _epoch++;
    final busy = _state.status == UpdateStatus.installing;
    if (!busy) {
      _token?.cancel();
      _cached = null;
      _etag = null;
      _lastChecked = null;
      _retryAfter = null;
      _verifiedPath = null;
      _verifiedFor = null;
      _state = const UpdateState();
    }
    _notify();
    await _writeString(UpdatePrefs.channel, value.name);
    await _remove(UpdatePrefs.cachedRelease);
    await _remove(UpdatePrefs.etag);
    await _remove(UpdatePrefs.lastCheckMs);
    await _remove(UpdatePrefs.retryAfterMs);
    if (!busy) await _sweep();
  }

  Future<void> dismissWhatsNew() async {
    if (_whatsNew == null) return;
    _whatsNew = null;
    _notify();
  }

  /// Fetches the notes for the running version into [whatsNew] (it starts out
  /// with none when the cache did not have them). Never throws.
  Future<void> loadWhatsNewNotes() async {
    await initialize();
    final current = _whatsNew;
    if (_disposed || current == null || current.notes.isNotEmpty) return;
    ReleaseInfo? fetched;
    try {
      fetched = await _repo.fetchByTag(current.tag, _installed.abis);
    } catch (e) {
      logUpdate('whats-new fetch failed: $e');
    }
    if (_disposed || fetched == null) return;
    if (_whatsNew?.id != current.id) return; // dismissed or replaced meanwhile
    _whatsNew = fetched;
    _notify();
  }

  // -- deriving state -------------------------------------------------------

  bool _isSkipped(ReleaseInfo r) => _skippedId == r.id;

  bool _isNewer(ReleaseInfo r) => isNewerRelease(
        installedName: _installed.versionName,
        installedBuild: _installed.versionCode,
        release: r,
      );

  bool _isSameBuild(ReleaseInfo r) {
    final a = AppVersion.parse(r.version).withBuild(r.build);
    final b = AppVersion.parse(_installed.versionName).withBuild(_installed.versionCode);
    return a == b;
  }

  String get _runningId => '${_installed.versionName}+${_installed.versionCode}';

  ReleaseInfo _notesLessRunning() {
    final v = AppVersion.parse(_installed.versionName);
    return ReleaseInfo(
      version: v.name,
      build: _installed.versionCode,
      tag: ReleaseInfo.tagFor(v.name, _installed.versionCode),
      channel: v.isPreRelease ? UpdateChannel.beta : UpdateChannel.stable,
      prerelease: v.isPreRelease,
    );
  }

  /// What the updater should show for [r]: the release to offer (or null) and
  /// a note when it is withheld on purpose.
  ({UpdateStatus status, ReleaseInfo? release, String? note}) _classify(ReleaseInfo? r) {
    if (r == null || !_isNewer(r)) {
      return (status: UpdateStatus.upToDate, release: null, note: null);
    }
    final need = r.minSdk;
    if (need != null && _installed.sdkInt > 0 && need > _installed.sdkInt) {
      return (
        status: UpdateStatus.upToDate,
        release: null,
        note: 'Needs Android ${androidVersionName(need)}',
      );
    }
    if (r.asset == null) {
      return (status: UpdateStatus.upToDate, release: null, note: null);
    }
    return (status: UpdateStatus.available, release: r, note: null);
  }

  /// Publishes the state that follows from [r]: available, ready (a verified
  /// file is already on disk), or up to date.
  Future<void> _applyRelease(ReleaseInfo? r, {String? error, bool initial = false}) async {
    final c = _classify(r);
    var status = c.status;
    final offered = c.release;
    if (offered != null && await _hasVerifiedFile(offered)) status = UpdateStatus.ready;
    if (_disposed) return;

    final ready = status == UpdateStatus.ready;
    final size = offered?.asset?.size ?? 0;
    final upToDate = status == UpdateStatus.upToDate;
    _state = UpdateState(
      // Before any check has finished there is nothing to claim "up to date".
      status: upToDate && initial && _lastChecked == null ? UpdateStatus.idle : status,
      release: offered,
      progress: ready ? 1 : 0,
      receivedBytes: ready ? size : 0,
      totalBytes: ready ? size : 0,
      error: error ?? c.note,
      checkedAt: _lastChecked,
    );
    _notify();
  }

  Future<void> _clearUpdate() async {
    _cached = null;
    _verifiedPath = null;
    _verifiedFor = null;
    await _remove(UpdatePrefs.cachedRelease);
    await _sweep();
    if (_disposed) return;
    _state = UpdateState(status: UpdateStatus.upToDate, checkedAt: _lastChecked);
    _notify();
  }

  // -- files ----------------------------------------------------------------

  Future<Directory?> _ensureDir() async {
    try {
      final dir = _dir ?? await _dirFn();
      await dir.create(recursive: true);
      return _dir = dir;
    } catch (e) {
      logUpdate('updates folder unavailable: $e');
      return null;
    }
  }

  /// True when the file for [r] is on disk and passes its checks. A leftover
  /// final-named file that does NOT pass is deleted - it can only be damage.
  Future<bool> _hasVerifiedFile(ReleaseInfo r) async {
    final asset = r.asset;
    final dir = _dir;
    if (asset == null || dir == null) return false;
    try {
      final known = _verifiedPath;
      if (_verifiedFor == r.id && known != null && await File(known).exists()) return true;
      final file = File(joinPath(dir, asset.name));
      if (!await file.exists()) return false;
      if (await _downloader.isVerified(file, asset)) {
        _verifiedFor = r.id;
        _verifiedPath = file.path;
        return true;
      }
      await file.delete();
    } catch (e) {
      logUpdate('verify check failed: $e');
    }
    return false;
  }

  /// Deletes everything in the updates folder except the finished or partial
  /// file for [keepFor] (so a restart can still resume), and any file that is
  /// not for the release on offer - which covers every APK at or below the
  /// installed version. Never throws.
  Future<void> _sweep({ReleaseInfo? keepFor}) async {
    final dir = _dir;
    if (dir == null) return;
    try {
      if (!await dir.exists()) return;
      final keep = <String>{};
      final a = keepFor?.asset;
      if (a != null) keep..add(a.name)..add('${a.name}.part');
      final entries = await dir.list(followLinks: false).toList();
      for (final e in entries) {
        if (e is! File || keep.contains(baseName(e.path))) continue;
        try {
          await e.delete();
        } catch (_) {}
      }
    } catch (e) {
      logUpdate('sweep failed: $e');
    }
  }

  Future<int> _lengthOf(File f) async {
    try {
      return await f.length();
    } catch (_) {
      return 0;
    }
  }

  // -- prefs ----------------------------------------------------------------

  void _readSettings() {
    _autoCheck = _readBool(UpdatePrefs.autoCheck) ?? true;
    _channel = UpdateChannel.parse(_readString(UpdatePrefs.channel));
    final last = _readInt(UpdatePrefs.lastCheckMs);
    _lastChecked = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
    _etag = _readString(UpdatePrefs.etag);
    _skippedId = _readString(UpdatePrefs.skippedVersion);
    _promptedId = _readString(UpdatePrefs.promptedVersion);
    final retry = _readInt(UpdatePrefs.retryAfterMs);
    _retryAfter = retry == null ? null : DateTime.fromMillisecondsSinceEpoch(retry);
  }

  ReleaseInfo? _readCache() {
    final raw = _readString(UpdatePrefs.cachedRelease);
    if (raw == null) return null;
    try {
      final map = asMap(jsonDecode(raw));
      if (map == null) throw const FormatException('cache is not an object');
      return ReleaseInfo.fromJson(map);
    } catch (e) {
      // An unreadable cache must not leave an ETag behind: a 304 would then
      // promise data we no longer have.
      logUpdate('dropping unreadable cached release: $e');
      _etag = null;
      unawaited(_remove(UpdatePrefs.cachedRelease));
      unawaited(_remove(UpdatePrefs.etag));
      return null;
    }
  }

  Object? _read(String key) {
    try {
      return _prefs?.get(key);
    } catch (_) {
      return null;
    }
  }

  String? _readString(String key) {
    final v = _read(key);
    return v is String && v.isNotEmpty ? v : null;
  }

  bool? _readBool(String key) {
    final v = _read(key);
    return v is bool ? v : null;
  }

  int? _readInt(String key) {
    final v = _read(key);
    return v is int ? v : null;
  }

  Future<void> _write(Future<bool> Function(SharedPreferences p) op) async {
    final p = _prefs;
    if (p == null) return;
    try {
      await op(p);
    } catch (e) {
      logUpdate('preferences write failed: $e');
    }
  }

  Future<void> _writeString(String key, String v) => _write((p) => p.setString(key, v));
  Future<void> _writeBool(String key, bool v) => _write((p) => p.setBool(key, v));
  Future<void> _writeInt(String key, int v) => _write((p) => p.setInt(key, v));
  Future<void> _remove(String key) => _write((p) => p.remove(key));

  Future<void> _clearBackoff() async {
    if (_retryAfter == null) return;
    _retryAfter = null;
    await _remove(UpdatePrefs.retryAfterMs);
  }

  // -- helpers --------------------------------------------------------------

  /// [f]'s result, or null if it throws.
  Future<T?> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      logUpdate('guarded call failed: $e');
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _waitPhrase(Duration d) {
    final minutes = d.inMinutes + (d.inSeconds % 60 > 0 ? 1 : 0);
    if (minutes <= 1) return 'in a minute';
    if (minutes < 60) return 'in about $minutes minutes';
    final hours = (minutes / 60).ceil();
    return hours == 1 ? 'in about an hour' : 'in about $hours hours';
  }
}

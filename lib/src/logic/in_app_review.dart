import 'dart:async';
import 'dart:io';
import 'package:get_storage/get_storage.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ReviewService {
  static const _boxKey = 'appPrefs';
  static const _firstOpenKey = 'first_open_at';
  static const _lastPromptKey = 'last_review_prompt_at';
  static const _versionPromptedKey = 'review_prompted_build';
  static const _launchCountKey = 'launch_count';
  static const _attemptedKey = 'review_prompt_attempted_at';

  static const int _minDaysSinceFirstOpen = 5;
  static const int _cooldownDays = 90;
  static const int _minLaunches = 7;

  static bool _isPrompting = false;
  static late final GetStorage _box;

  static Future<void> init() async {
    await GetStorage.init(_boxKey);
    _box = GetStorage(_boxKey);

    if (_box.read(_firstOpenKey) == null) {
      _box.write(_firstOpenKey, DateTime.now().toUtc().toIso8601String());
    }
    final launches = (_box.read(_launchCountKey) ?? 0) + 1;
    _box.write(_launchCountKey, launches);
  }

  static DateTime _parseUtcOr(String? s, DateTime fallback) {
    if (s == null) return fallback;
    final parsed = DateTime.tryParse(s);
    return (parsed == null) ? fallback : parsed.toUtc();
  }

  static Future<void> maybePrompt({
    bool force = false,
    String? appStoreId,
  }) async {
    if (_isPrompting) return;
    _isPrompting = true;

    try {
      final nowUtc = DateTime.now().toUtc();

      final firstOpenUtc = _parseUtcOr(_box.read(_firstOpenKey), nowUtc);
      final lastPromptUtc = _parseUtcOr(
        _box.read(_lastPromptKey),
        DateTime.utc(1970),
      );
      final attemptedUtc = _parseUtcOr(
        _box.read(_attemptedKey),
        DateTime.utc(1970),
      );

      final launches = _box.read(_launchCountKey) ?? 0;

      final info = await PackageInfo.fromPlatform();
      final currentBuildKey = '${info.packageName}-${info.buildNumber}';
      final alreadyPromptedThisBuild =
          _box.read(_versionPromptedKey) == currentBuildKey;

      if (!force) {
        if (nowUtc.difference(firstOpenUtc).inDays < _minDaysSinceFirstOpen) {
          return;
        }
        if (launches < _minLaunches) return;
        if (alreadyPromptedThisBuild) return;
        if (nowUtc.difference(lastPromptUtc).inDays < _cooldownDays) return;
        if (nowUtc.difference(attemptedUtc).inHours < 24) return;
      }

      final inAppReview = InAppReview.instance;
      try {
        final available = await inAppReview.isAvailable();
        if (available) {
          await inAppReview.requestReview();
        } else {
          if (Platform.isIOS && (appStoreId == null || appStoreId.isEmpty)) {
            return;
          }
          await inAppReview.openStoreListing(appStoreId: appStoreId);
        }

        _box.write(_lastPromptKey, DateTime.now().toUtc().toIso8601String());
        _box.write(_versionPromptedKey, currentBuildKey);
      } catch (_) {
        _box.write(_attemptedKey, DateTime.now().toUtc().toIso8601String());
      }
    } finally {
      _isPrompting = false;
    }
  }
}

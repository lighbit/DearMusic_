import 'dart:io';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:get_storage/get_storage.dart';
import 'package:flutter/material.dart';

class BatteryHelper {
  static final _box = GetStorage('dearmusic');
  static const _kAskedOnce = 'dm_battery_asked_once';
  static const _ch = MethodChannel('dearmusic/battery');

  static Future<bool> isIgnoringOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _ch.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;

    final packageInfo = await PackageInfo.fromPlatform();
    final pkg = packageInfo.packageName;

    try {
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:$pkg',
        arguments: {
          ':settings:fragment_args_key': 'app_battery_usage',
          ':settings:show_fragment_args': {
            ':settings:fragment_args_key': 'app_battery_usage',
          },
        },
      );
      await intent.launch();
      return;
    } catch (_) {}

    try {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$pkg',
        arguments: {
          ':settings:fragment_args_key': 'battery',
          ':settings:show_fragment_args': {
            ':settings:fragment_args_key': 'battery',
          },
        },
      );
      await intent.launch();
    } catch (e) {
      debugPrint('Gagal membuka pengaturan aplikasi: $e');
    }
  }

  static Future<void> maybeAskUnrestricted(BuildContext context) async {
    if (!Platform.isAndroid) return;

    if (await isIgnoringOptimizations()) return;

    if (_box.read<bool>(_kAskedOnce) == true) return;

    final ok = await _showUnrestrictedDialog(context);
    _box.write(_kAskedOnce, true);
    if (ok == true) {
      await openBatterySettings();
    }
  }

  static Future<void> showUnrestrictedPrompt(BuildContext context) async {
    HapticFeedback.lightImpact();
    if (!Platform.isAndroid) return;
    final ok = await _showUnrestrictedDialog(context);
    if (ok == true) {
      await openBatterySettings();
    }
  }

  static Future<bool> _showUnrestrictedDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(easy.tr('batteryDialog.title')),
        content: Text(easy.tr('batteryDialog.content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(easy.tr('batteryDialog.later')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(easy.tr('batteryDialog.allow')),
          ),
        ],
      ),
    ).then((v) => v ?? false);
  }
}

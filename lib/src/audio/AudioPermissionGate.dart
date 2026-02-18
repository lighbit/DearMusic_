import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  PermissionService._();

  static final instance = PermissionService._();

  Future<int> _sdk() async {
    if (!Platform.isAndroid) return 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  }

  Future<Permission> _mediaPermission() async {
    final sdk = await _sdk();
    return sdk >= 33 ? Permission.audio : Permission.storage;
  }

  Future<bool> isGranted() async {
    if (!Platform.isAndroid) return true;
    final p = await _mediaPermission();
    return (await p.status).isGranted;
  }

  Future<bool> ensure({bool force = false}) async {
    if (!Platform.isAndroid) return true;
    final p = await _mediaPermission();
    var st = await p.status;

    if (st.isGranted) return true;

    if (st.isPermanentlyDenied) {
      debugPrint('[perm] permanentlyDenied=true -> open settings');
      return false;
    }

    if (force || st.isDenied || st.isLimited || st.isRestricted) {
      debugPrint('[perm] requesting… prev=${st.name}');
      final req = await p.request();
      debugPrint('[perm] result=${req.name}');
      return req.isGranted;
    }

    return false;
  }

  Future<bool> ensureForOnAudioQuery(
    OnAudioQuery query, {
    bool force = false,
  }) async {
    final ok = await ensure(force: force);
    if (!ok) return false;

    bool qOk = false;
    try {
      qOk = await query.permissionsStatus();
      if (!qOk) {
        qOk = await query.permissionsRequest();
      }
    } catch (_) {
      qOk = false;
    }
    return qOk;
  }

  Future<bool> isPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    final p = await _mediaPermission();
    final st = await p.status;
    return st.isPermanentlyDenied;
  }

  Future<bool> openSettings() => openAppSettings();
}

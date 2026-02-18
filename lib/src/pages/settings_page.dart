import 'package:dearmusic/main.dart';
import 'package:dearmusic/src/logic/pin_hub.dart';
import 'package:dearmusic/src/logic/usage_tracker.dart';
import 'package:dearmusic/src/pages/wrapped_page.dart';
import 'package:dearmusic/src/player_scope.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../audio/system_audio.dart';
import '../logic/battery_helper.dart';

class SettingsKeys {
  static const crossfadeSec = 'st_crossfade_sec';
  static const skipSilent = 'st_skip_intro';
  static const smartOutro = 'st_smart_outro';
  static const replayGain = 'st_rg_enable';
  static const themeMode = 'st_theme_mode';
  static const preferEmbeddedArt = 'st_prefer_embedded';
  static const hiResArtwork = 'st_hires_art';
  static const scanAll = 'st_scan_all';
  static const allowedDirs = 'st_allowed_dirs';
  static const showQuickAccess = 'st_show_quick_access';
  static const autoplayEnabled = 'st_autoplay_enabled';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final box = GetStorage();
  final query = OnAudioQuery();
  final info = PackageInfo.fromPlatform();

  double getD(String k, double def) {
    final v = box.read(k);
    if (v is num) return v.toDouble();
    return def;
  }

  int getI(String k, int def) {
    final v = box.read(k);
    if (v is num) return v.toInt();
    return def;
  }

  bool getB(String k, bool def) {
    final v = box.read(k);
    return v is bool ? v : def;
  }

  String getS(String k, String def) {
    final v = box.read(k);
    return v is String ? v : def;
  }

  Future<void> setVal(String k, dynamic v) async {
    HapticFeedback.selectionClick();
    await box.write(k, v);
    if (mounted) setState(() {});
  }

  Future<bool> _hasRecapData() async {
    try {
      final now = DateTime.now();
      final yearly = await UsageTracker.instance.getWrappedStats(
        sinceEpochMs: DateTime(now.year, 1, 1).millisecondsSinceEpoch,
        untilEpochMs: now.millisecondsSinceEpoch,
        topN: 1,
      );
      final hasYear =
          yearly.totalPlays > 0 ||
          yearly.listenMs > 0 ||
          yearly.discoveryCount > 0;
      if (hasYear) return true;

      final all = await UsageTracker.instance.getWrappedStats(topN: 1);
      debugPrint(
        "all ${all.totalPlays}, ${all.listenMs}, ${all.discoveryCount}",
      );
      return all.totalPlays > 0 || all.listenMs > 0 || all.discoveryCount > 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: theme.scaffoldBackgroundColor,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: PopScope(
        canPop: true,
        onPopInvoked: (didPop) {},
        child: Scaffold(
          appBar: AppBar(
            systemOverlayStyle: overlay,
            title: Text(easy.tr("settings.title")),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
            ),
            elevation: 0.5,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            iconTheme: IconThemeData(color: cs.primary),
          ),
          body: ListView(
            children: [
              _section(easy.tr("settings.section.playback")),

              _tileSlider(
                title: easy.tr("settings.crossfade"),
                value: getD(SettingsKeys.crossfadeSec, 0),
                min: 0,
                max: 12,
                step: 1,
                labelBuilder: (v) => '${v.round()} s',
                onChanged: (v) async {
                  await setVal(SettingsKeys.crossfadeSec, v);
                  setVal(SettingsKeys.skipSilent, false);
                  final ctrl = PlayerScope.of(context);
                  await ctrl.setCrossfade(v.round());
                },
              ),

              _tileSwitch(
                title: easy.tr("settings.autoplay.title"),
                subtitle: easy.tr("settings.autoplay.subtitle"),
                value: getB(SettingsKeys.autoplayEnabled, true),
                onChanged: (v) async =>
                    await setVal(SettingsKeys.autoplayEnabled, v),
              ),

              _tileSwitch(
                title: easy.tr("settings.skipIntro.title"),
                subtitle: easy.tr("settings.skipIntro.subtitle"),
                value: getB(SettingsKeys.skipSilent, false),
                onChanged: (value) async {
                  final cf =
                      (box.read('st_crossfade_sec') as num?)?.toInt() ?? 0;
                  await setVal(SettingsKeys.skipSilent, value);
                  if (cf > 0) {
                    await setVal(SettingsKeys.crossfadeSec, 0);
                  }
                },
              ),

              _tileSwitch(
                title: easy.tr("settings.replayGain.title"),
                subtitle: easy.tr("settings.replayGain.subtitle"),
                value: getB(SettingsKeys.replayGain, false),
                onChanged: (v) async {
                  await setVal(SettingsKeys.replayGain, v);
                  final ctrl = PlayerScope.of(context);
                  await ctrl.setReplayGainEnabled(v);
                },
              ),

              _tileDropdown<int>(
                title: easy.tr("settings.theme.title"),
                value: themeService.currentIndex,
                items: {
                  0: easy.tr("settings.theme.system"),
                  1: easy.tr("settings.theme.light"),
                  2: easy.tr("settings.theme.dark"),
                },
                onChanged: (v) {
                  themeService.setThemeIndex(v);
                },
              ),

              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(easy.tr("settings.language.title")),
                subtitle: Text(easy.tr("settings.language.subtitle")),
                trailing: DropdownButton<Locale>(
                  value: context.locale,
                  items: [
                    DropdownMenuItem(
                      value: const Locale('id'),
                      child: Text(easy.tr("settings.language.id")),
                    ),
                    DropdownMenuItem(
                      value: const Locale('en'),
                      child: Text(easy.tr("settings.language.en")),
                    ),
                  ],
                  onChanged: (loc) async {
                    if (loc == null) return;
                    HapticFeedback.selectionClick();
                    await context.setLocale(loc);

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(easy.tr("settings.language.changed")),
                        ),
                      );
                    }

                    if (mounted) setState(() {});
                  },
                ),
              ),

              _tileSwitch(
                title: easy.tr("settings.embeddedArt"),
                value: getB(SettingsKeys.preferEmbeddedArt, true),
                onChanged: (v) => setVal(SettingsKeys.preferEmbeddedArt, v),
              ),
              _tileSwitch(
                title: easy.tr("settings.hiResArt"),
                value: getB(SettingsKeys.hiResArtwork, true),
                onChanged: (v) => setVal(SettingsKeys.hiResArtwork, v),
              ),

              ListTile(
                leading: const Icon(Icons.delete_sweep_rounded),
                title: Text(easy.tr("settings.clearCache")),
                onTap: () {
                  HapticFeedback.lightImpact();
                  imageCache.clear();
                  imageCache.clearLiveImages();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(easy.tr("settings.clearCache.done")),
                    ),
                  );
                },
              ),

              _section(easy.tr("settings.section.device")),
              ListTile(
                leading: const Icon(Icons.equalizer_rounded),
                title: Text(easy.tr("settings.equalizer")),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  final ok = await SystemAudio.openEqualizer(
                    PlayerScope.of(context).player,
                  );
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          easy.tr("settings.equalizer.unavailable"),
                        ),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.speaker_rounded),
                title: Text(easy.tr("settings.output")),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await SystemAudio.openOutputSwitcher();
                },
              ),

              _section(easy.tr("settings.section.privacy")),

              FutureBuilder<bool>(
                future: _hasRecapData(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox.shrink();
                  }
                  if (snap.data != true) return const SizedBox.shrink();

                  return ListTile(
                    leading: const Icon(Icons.auto_graph_rounded),
                    title: Text(easy.tr("settings.recap.title")),
                    subtitle: Text(easy.tr("settings.recap.subtitle")),
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      if (!mounted) return;

                      final ok = await _hasRecapData();
                      if (!ok) return;

                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WrappedStoryPage(),
                        ),
                      );
                    },
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.push_pin_rounded),
                title: Text(easy.tr("settings.clearPins.title")),
                subtitle: Text(easy.tr("settings.clearPins.subtitle")),
                onTap: () async {
                  HapticFeedback.lightImpact();

                  final ok = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                      title: Text(easy.tr("settings.clearPins.confirmTitle")),
                      content: Text(
                        easy.tr("settings.clearPins.confirmMessage"),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(ctx, false);
                          },
                          child: Text(easy.tr("common.cancel")),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(ctx, true);
                          },
                          child: Text(easy.tr("common.clearAllPins")),
                        ),
                      ],
                    ),
                  );

                  if (ok != true) return;

                  final removed = await PinHub.I.deleteAllPins();
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        easy.tr(
                          "settings.clearPins.done",
                          namedArgs: {"count": "$removed"},
                        ),
                      ),
                    ),
                  );

                  setState(() {});
                },
              ),

              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: Text(easy.tr("settings.resetRecs.title")),
                subtitle: Text(easy.tr("settings.resetRecs.subtitle")),
                onTap: () async {
                  HapticFeedback.lightImpact();

                  final confirm = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) {
                      return AlertDialog(
                        title: Text(easy.tr("settings.resetRecs.confirmTitle")),
                        content: Text(
                          easy.tr("settings.resetRecs.confirmMessage"),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop(false);
                            },
                            child: Text(easy.tr("common.cancel")),
                          ),
                          FilledButton.tonal(
                            onPressed: () {
                              Navigator.of(ctx).pop(true);
                            },
                            child: Text(easy.tr("common.yesReset")),
                          ),
                        ],
                      );
                    },
                  );

                  if (confirm != true) return;

                  await _resetRecommendations();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(easy.tr("settings.resetRecs.done")),
                      ),
                    );
                  }
                },
              ),

              ListTile(
                leading: const Icon(Icons.battery_saver_rounded),
                title: Text(easy.tr("settings.battery.title")),
                subtitle: Text(easy.tr("settings.battery.subtitle")),
                onTap: () => BatteryHelper.showUnrestrictedPrompt(context),
              ),

              _section(easy.tr("settings.section.home")),
              _tileSwitch(
                title: easy.tr("settings.quickAccess.title"),
                subtitle: easy.tr("settings.quickAccess.subtitle"),
                value: getB(SettingsKeys.showQuickAccess, true),
                onChanged: (v) async =>
                    await setVal(SettingsKeys.showQuickAccess, v),
              ),

              _section(easy.tr("settings.section.library")),
              _tileSwitch(
                title: easy.tr("settings.scanAll.title"),
                subtitle: easy.tr("settings.scanAll.subtitle"),
                value: getB(SettingsKeys.scanAll, true),
                onChanged: (v) async => await setVal(SettingsKeys.scanAll, v),
              ),

              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(easy.tr("settings.folders.title")),
                subtitle: Builder(
                  builder: (context) {
                    final dirs =
                        (box
                            .read<List>(SettingsKeys.allowedDirs)
                            ?.cast<String>()) ??
                        const [];
                    if (getB(SettingsKeys.scanAll, true)) {
                      return Text(easy.tr("settings.folders.default"));
                    }
                    if (dirs.isEmpty) {
                      return Text(easy.tr("settings.folders.empty"));
                    }
                    return Text(dirs.join('\n'));
                  },
                ),
                trailing: IconButton(
                  tooltip: easy.tr("settings.addFolder"),
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    try {
                      final path = await getDirectoryPath(
                        confirmButtonText: 'choose',
                      );
                      if (path == null) return;

                      final dirs =
                          (box
                              .read<List>(SettingsKeys.allowedDirs)
                              ?.cast<String>()) ??
                          <String>[];
                      if (!dirs.contains(path)) dirs.add(path);

                      await setVal(SettingsKeys.allowedDirs, dirs);
                      await setVal(SettingsKeys.scanAll, false);

                      if (mounted) setState(() {});
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(easy.tr("settings.addFolder.fail")),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),

              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: Text(easy.tr("settings.clearFolders")),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await setVal(SettingsKeys.allowedDirs, <String>[]);
                },
              ),

              const SizedBox(height: 6),
              const Divider(),
              const SizedBox(height: 6),

              Center(
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 40,
                        width: 40,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }

                    final info = snapshot.data!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          easy.tr(
                            "settings.version",
                            namedArgs: {
                              "version": info.version,
                              "build": info.buildNumber,
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text("© DearMusic 🎧 2025"),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  Widget _tileSwitch({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _tileSlider({
    required String title,
    required double value,
    required double min,
    required double max,
    required double step,
    required String Function(double) labelBuilder,
    required ValueChanged<double> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      trailing: Text(labelBuilder(value)),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: ((max - min) / step).round(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _tileDropdown<T>({
    required String title,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<T>(
        value: value,
        items: items.entries
            .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Future<void> _resetRecommendations() async {
    UsageTracker.instance.resetAll();
  }
}

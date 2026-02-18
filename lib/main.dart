import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:dearmusic/src/audio/loudness_analysis_service.dart';
import 'package:dearmusic/src/audio/smart_intro_outro_service.dart';
import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/logic/in_app_review.dart';
import 'package:dearmusic/src/logic/usage_tracker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:home_widget/home_widget.dart';
import 'package:in_app_update/in_app_update.dart';

import 'package:dearmusic/src/logic/theme_service.dart';
import 'package:dearmusic/src/player_scope.dart';
import 'package:dearmusic/src/app_shell.dart';
import 'src/theme.dart';

Future<void> _backgroundCallback(Uri? uri) async {
  if (uri?.host == 'refresh') {
    await HomeWidget.updateWidget(name: 'DearMusicWidgetProvider');
  }
}

late final ThemeService themeService;
late final PlayerController _audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("🟡 [BOOT] Flutter bindings initialized");

  await UsageTracker.instance.init();
  await LoudnessService.init();
  await SmartIntroOutroService.init();
  debugPrint("🟡 [BOOT] Database SQLite initialized");

  debugPrint("🟡 [BOOT] Locking orientation to portrait…");
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  debugPrint("✅ [BOOT] Orientation locked (portrait only)");

  debugPrint("🟡 [BOOT] Initializing localization…");
  await EasyLocalization.ensureInitialized();
  debugPrint("✅ [BOOT] Localization ready");

  debugPrint("🟡 [BOOT] Initializing review service…");
  unawaited(ReviewService.init());
  debugPrint("✅ [BOOT] Review service ready");

  debugPrint("🟡 [BOOT] Initializing theme service…");
  themeService = ThemeService();
  await themeService.init();
  debugPrint("✅ [BOOT] Theme service ready");

  debugPrint("🟡 [BOOT] Registering HomeWidget background callback…");
  unawaited(HomeWidget.registerBackgroundCallback(_backgroundCallback));
  debugPrint("✅ [BOOT] HomeWidget background callback registered");

  debugPrint("🟡 [BOOT] Creating AudioService / PlayerController…");
  _audioHandler = await AudioService.init<PlayerController>(
    builder: () => PlayerController(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dearmusic_mvp.playback',
      androidNotificationChannelName: 'DearMusic Playback',
      androidNotificationOngoing: false,
      notificationColor: Color(0xFF6C63FF),
      androidNotificationIcon: 'drawable/ic_stat_notify',
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: false,
      fastForwardInterval: Duration(seconds: 15),
      rewindInterval: Duration(seconds: 15),
    ),
  );
  debugPrint("✅ [BOOT] AudioService created");

  debugPrint("🟡 [BOOT] Initializing PlayerController handler…");
  unawaited(_audioHandler.initHandler());
  debugPrint("✅ [BOOT] PlayerController handler ready");

  debugPrint("🟡 [BOOT] Updating home widget…");
  HomeWidget.updateWidget(name: 'DearMusicWidgetProvider');
  debugPrint("✅ [BOOT] Home widget updated");

  debugPrint("🟡 [BOOT] Attaching ArtworkMemCache to media query…");
  ArtworkMemCache.I.attachQuery(_audioHandler.query);
  debugPrint("✅ [BOOT] ArtworkMemCache attached");

  debugPrint("🟡 [BOOT] Launching DearMusicApp…");
  runApp(
    ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return EasyLocalization(
          supportedLocales: const [Locale('id'), Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('id'),
          child: PlayerScope(
            controller: _audioHandler,
            child: const DearMusicApp(),
          ),
        );
      },
    ),
  );
  debugPrint("✅ [BOOT] DearMusicApp running");
}

void checkForUpdate() async {
  try {
    final info = await InAppUpdate.checkForUpdate();

    if (info.updateAvailability == UpdateAvailability.updateAvailable &&
        info.flexibleUpdateAllowed) {
      final result = await InAppUpdate.startFlexibleUpdate().catchError((e) {
        debugPrint("startFlexibleUpdate failed: $e");
        return AppUpdateResult.inAppUpdateFailed;
      });

      if (result == AppUpdateResult.success) {
        try {
          await InAppUpdate.completeFlexibleUpdate();
        } catch (e) {
          debugPrint("completeFlexibleUpdate failed: $e");
        }
      }
    }
  } catch (e) {
    debugPrint("Update check failed: $e");
  }
}

class DearMusicApp extends StatefulWidget {
  const DearMusicApp({super.key});

  @override
  State<DearMusicApp> createState() => _DearMusicAppState();
}

class _DearMusicAppState extends State<DearMusicApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    debugPrint("⬆️ [UPDATE] checkForUpdate mulai");
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await Future.delayed(const Duration(milliseconds: 400));
        checkForUpdate();
      } catch (e) {
        debugPrint("❌ [UPDATE] gagal: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const fallbackSeed = Color(0xFF6750A4);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme = buildColorScheme(
          lightDynamic,
          Brightness.light,
          fallbackSeed,
        );
        final darkScheme = buildColorScheme(
          darkDynamic,
          Brightness.dark,
          fallbackSeed,
        );

        final lightTheme = buildTheme(lightScheme);
        final darkTheme = buildTheme(darkScheme);

        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeService.themeMode,
          builder: (_, mode, __) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'DearMusic',
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: mode,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const AppShell(),
            );
          },
        );
      },
    );
  }
}

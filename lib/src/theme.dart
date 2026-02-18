import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

ColorScheme buildColorScheme(ColorScheme? dyn, Brightness b, Color seed) {
  return dyn?.harmonized() ??
      ColorScheme.fromSeed(seedColor: seed, brightness: b);
}

ThemeData buildTheme(ColorScheme scheme) {
  final base = Typography.material2021(platform: TargetPlatform.android);
  final materialBase = scheme.brightness == Brightness.dark
      ? base.white
      : base.black;

  final pjText = GoogleFonts.plusJakartaSansTextTheme(materialBase).copyWith(
    displayLarge: GoogleFonts.plusJakartaSans(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    headlineLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    headlineMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),

    bodyLarge: GoogleFonts.plusJakartaSans(
      fontWeight: FontWeight.w500,
      height: 1.20,
    ),
    bodyMedium: GoogleFonts.plusJakartaSans(
      fontWeight: FontWeight.w500,
      height: 1.20,
    ),
    bodySmall: GoogleFonts.plusJakartaSans(
      fontWeight: FontWeight.w500,
      height: 1.15,
    ),

    labelLarge: GoogleFonts.spaceGrotesk(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.0,
    ),
    labelMedium: GoogleFonts.spaceGrotesk(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.0,
    ),
    labelSmall: GoogleFonts.spaceGrotesk(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.0,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: pjText.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20.sp,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    sliderTheme: const SliderThemeData(
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      strokeCap: StrokeCap.round,
      strokeWidth: 8.0,
      linearMinHeight: 10.0,
      borderRadius: const BorderRadius.all(Radius.circular(5.0)),
      trackGap: 4.0,
    ),
  );
}

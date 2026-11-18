import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class Phantom {
  static const background = Color(0xFF050505);
  static const surface = Color(0xFF101010);
  static const raised = Color(0xFF191919);
  static const paper = Color(0xFFF5F5F5);
  static const secondary = Color(0xFFA4A4A4);
  static const line = Color(0x22FFFFFF);
  static const ease = Cubic(.16, 1, .3, 1);
  static const font = 'Inter';
  static const fallback = ['Inter Cyrillic'];
  static const monochrome = ColorFilter.matrix([
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  static const heading = TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -1.35, height: 1.12);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.15, color: secondary);
  static const data = TextStyle(fontSize: 11, color: secondary, fontFeatures: [FontFeature.tabularFigures()]);

  static RoundedRectangleBorder shape(double radius) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: const BorderSide(color: line),
  );

  static ThemeData theme() {
    final base = ThemeData.dark(useMaterial3: true);
    final rounded = shape(14);
    const pill = StadiumBorder();
    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      cardColor: surface,
      dividerColor: line,
      colorScheme: base.colorScheme.copyWith(
        primary: paper,
        onPrimary: background,
        secondary: paper,
        surface: surface,
        onSurface: paper,
        onSurfaceVariant: secondary,
        primaryContainer: raised,
        onPrimaryContainer: paper,
        secondaryContainer: raised,
        onSecondaryContainer: paper,
        outline: secondary,
        outlineVariant: line,
        surfaceContainerHighest: raised,
        surfaceContainerHigh: raised,
        surfaceContainer: surface,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: font,
        fontFamilyFallback: fallback,
        bodyColor: paper,
        displayColor: paper,
      ),
      iconTheme: const IconThemeData(color: paper),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: font,
          fontFamilyFallback: fallback,
          color: paper,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.55,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: secondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: secondary),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: secondary,
        textColor: paper,
        titleTextStyle: const TextStyle(
          fontFamily: font,
          fontFamilyFallback: fallback,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: const TextStyle(
          fontFamily: font,
          fontFamilyFallback: fallback,
          fontSize: 12,
          color: secondary,
        ),
        shape: rounded,
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: pill)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          side: const BorderSide(color: line),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: pill)),
      chipTheme: const ChipThemeData(
        shape: pill,
        side: BorderSide(color: line),
        backgroundColor: surface,
        selectedColor: Color(0xFF333333),
        labelStyle: TextStyle(
          fontFamily: font,
          fontFamilyFallback: fallback,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: paper,
        ),
        secondaryLabelStyle: TextStyle(fontFamily: font, fontFamilyFallback: fallback, color: paper),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(pill),
          side: const WidgetStatePropertyAll(BorderSide(color: line)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? const Color(0xFF333333) : surface,
          ),
          foregroundColor: const WidgetStatePropertyAll(paper),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 2,
        activeTrackColor: paper,
        inactiveTrackColor: Color(0xFF444444),
        thumbColor: paper,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? paper : raised),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? surface : secondary,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(line),
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: line,
        indicatorColor: paper,
        labelColor: paper,
        unselectedLabelColor: secondary,
      ),
      dialogTheme: DialogThemeData(backgroundColor: raised, surfaceTintColor: Colors.transparent, shape: shape(24)),
      popupMenuTheme: PopupMenuThemeData(color: raised, surfaceTintColor: Colors.transparent, shape: rounded),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised,
        behavior: SnackBarBehavior.floating,
        shape: rounded,
        contentTextStyle: const TextStyle(color: paper),
      ),
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class PhantomPanel extends StatelessWidget {
  const PhantomPanel({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding,
    this.solid = false,
    this.selected = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool solid, selected;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: Phantom.shape(radius),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? const [Color(0x33FFFFFF), Color(0x1FFFFFFF)]
              : solid
              ? const [Phantom.raised, Phantom.surface]
              : const [Color(0x1AFFFFFF), Color(0x09FFFFFF)],
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    ),
  );
}

class PhantomRings extends StatelessWidget {
  const PhantomRings({super.key, this.emphasis = 1});
  final double emphasis;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _RingsPainter(emphasis), child: const SizedBox.expand()),
  );
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter(this.emphasis);
  final double emphasis;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    if (radius <= 0) return;
    final rings = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 5; i++) {
      rings.color = Colors.white.withValues(alpha: (.12 - i * .013) * emphasis);
      canvas.drawCircle(center, radius * i / 5, rings);
    }
    final rect = Rect.fromCircle(center: center, radius: radius * .8);
    rings.color = Colors.white.withValues(alpha: .27 * emphasis);
    rings.strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi * .74, math.pi * .38, false, rings);
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) => oldDelegate.emphasis != emphasis;
}

class PhantomArtworkPlaceholder extends StatelessWidget {
  const PhantomArtworkPlaceholder({super.key, required this.size, this.title});
  final double size;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final initials = (title ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    final label = initials.isEmpty ? null : initials;
    return ColoredBox(
      color: Phantom.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const PhantomRings(),
          Center(
            child: label == null
                ? Icon(Icons.graphic_eq, color: Phantom.secondary, size: size * .35)
                : Text(
                    label,
                    style: TextStyle(color: Phantom.paper, fontSize: size * .28, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
          ),
        ],
      ),
    );
  }
}

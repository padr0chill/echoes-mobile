import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'services/store.dart';

/// Масштаб интерфейса от ширины экрана: iPhone SE … Pro Max … iPad — одни и те же пропорции.
/// Базовая ширина — 390 (iPhone 12–15). Отступы и размеры умножаются на k, текст — через textScaler.
extension UiScale on BuildContext {
  double get k {
    final w = MediaQuery.sizeOf(this).width;
    final h = MediaQuery.sizeOf(this).height;
    final short = w < h ? w : h;
    return (short / 390).clamp(0.82, 1.45);
  }

  double u(double v) => v * k;

  bool get wide => MediaQuery.sizeOf(this).width >= 720;

  Color get accent => Store.instance.accent;

  /// Тема «Эховамп» (Winamp): всё квадратное, с фасками.
  bool get echoamp => Store.instance.winamp;

  /// Скругление: в Эховампе — 0 (углы прямые, как в Winamp).
  double r(double v) => echoamp ? 0 : u(v);

  /// Форма «пилюли» для кнопок: в Эховампе — прямоугольник.
  OutlinedBorder get pill => echoamp ? const RoundedRectangleBorder() : const StadiumBorder();
}

/// Переключить вкладку из глубины экрана (например, капсула «Для вас» на волне). Слушает Shell.
final openTab = ValueNotifier<int?>(null);

const _waMono = 'Menlo';
const _waMonoFallback = ['Courier', 'monospace'];

/// Тема «Эховамп» — весь интерфейс как Winamp 2: чёрные «плейлисты» с зелёным моноширинным текстом,
/// серые панели и кнопки с фасками, прямые углы, без размытий.
ThemeData _echoampTheme() {
  const green = Color(0xFF00E000), body = Color(0xFF262638), hi = Color(0xFF5E5E7A), btn = Color(0xFF3A3A50);
  const text = Color(0xFFE6E6EE);
  final base = ThemeData.dark(useMaterial3: true);
  const square = RoundedRectangleBorder(side: BorderSide(color: hi, width: 1.2));
  final btnStyle = ButtonStyle(
    shape: const WidgetStatePropertyAll(square),
    backgroundColor: const WidgetStatePropertyAll(btn),
    foregroundColor: const WidgetStatePropertyAll(text),
    textStyle: const WidgetStatePropertyAll(
        TextStyle(fontFamily: _waMono, fontFamilyFallback: _waMonoFallback, fontWeight: FontWeight.w700)),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Colors.black,
    colorScheme: base.colorScheme.copyWith(
      primary: green,
      secondary: green,
      surface: body,
      onPrimary: Colors.black,
      onSurface: green,
      secondaryContainer: const Color(0xFF0B3A0B),
      onSecondaryContainer: green,
    ),
    cardColor: const Color(0xFF14141E),
    dividerColor: hi.withValues(alpha: 0.5),
    textTheme: base.textTheme.apply(
      fontFamily: _waMono,
      fontFamilyFallback: _waMonoFallback,
      bodyColor: green,
      displayColor: green,
    ),
    iconTheme: const IconThemeData(color: text),
    appBarTheme: const AppBarTheme(
      backgroundColor: body,
      foregroundColor: green,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: Color(0xFF0C0C12), width: 1.5)),
      titleTextStyle: TextStyle(
          fontFamily: _waMono,
          fontFamilyFallback: _waMonoFallback,
          color: green,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(style: btnStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: btnStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: btnStyle),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        foregroundColor: const WidgetStatePropertyAll(green),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: _waMono, fontFamilyFallback: _waMonoFallback)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        side: const WidgetStatePropertyAll(BorderSide(color: hi)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : btn),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? green : text),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: btn,
      selectedColor: Colors.black,
      side: BorderSide(color: hi),
      shape: RoundedRectangleBorder(),
      labelStyle: TextStyle(fontFamily: _waMono, fontFamilyFallback: _waMonoFallback, color: green),
    ),
    switchTheme: SwitchThemeData(
      thumbColor:
          WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? green : const Color(0xFF8A8AA0)),
      trackColor:
          WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF0B3A0B) : btn),
      trackOutlineColor: const WidgetStatePropertyAll(hi),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: green,
      thumbColor: const Color(0xFF8A8AA0),
      inactiveTrackColor: const Color(0xFF0B3A0B),
      trackHeight: 4,
      overlayShape: SliderComponentShape.noOverlay,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.black,
      border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: hi)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: hi)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: green)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: text, textColor: green),
    dialogTheme: const DialogThemeData(backgroundColor: body, shape: square),
    popupMenuTheme: const PopupMenuThemeData(color: body, shape: square),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.black,
      contentTextStyle: TextStyle(fontFamily: _waMono, fontFamilyFallback: _waMonoFallback, color: green),
      shape: square,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: green),
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

ThemeData buildTheme(Color accent, bool light, {bool winamp = false}) {
  if (winamp) return _echoampTheme();
  final base = light ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);
  final bg = winamp ? const Color(0xFF1B1B29) : (light ? const Color(0xFFF4F3F0) : const Color(0xFF0E0E10));
  // карточки — полупрозрачные (стекло без размытия: дёшево даже в длинных списках); в Winamp — плоские серые
  final card = winamp
      ? const Color(0xFF2A2A36)
      : (light ? Colors.white.withValues(alpha: 0.62) : Colors.white.withValues(alpha: 0.075));
  final text = light ? const Color(0xFF141416) : Colors.white;
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      surface: card,
      onPrimary: Colors.black,
    ),
    cardColor: card,
    dividerColor: text.withValues(alpha: 0.08),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0)
        .copyWith(foregroundColor: text),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent),
    // окна и меню — непрозрачные (surface полупрозрачный ради карточек)
    dialogTheme: DialogThemeData(backgroundColor: light ? Colors.white : const Color(0xFF1E1E23)),
    popupMenuTheme: PopupMenuThemeData(
      color: light ? Colors.white : const Color(0xFF1E1E23),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    // строки меню, настроек, списков — подсветка нажатия скруглённая, а не прямоугольная
    listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: light ? const Color(0xEE1C1C20) : const Color(0xEE2A2A30),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: text.withValues(alpha: 0.06),
      selectedColor: accent.withValues(alpha: 0.25),
      side: BorderSide(color: text.withValues(alpha: 0.12)),
      shape: const StadiumBorder(),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      thumbColor: accent,
      inactiveTrackColor: text.withValues(alpha: 0.15),
      overlayShape: SliderComponentShape.noOverlay,
      trackHeight: 3,
    ),
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    iconTheme: IconThemeData(color: text),
    splashFactory: InkSparkle.splashFactory,
    // переходы между экранами — как в iOS (плавный сдвиг и «свайп назад» от края)
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

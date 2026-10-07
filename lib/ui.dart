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
}

ThemeData buildTheme(Color accent, bool light) {
  final base = light ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);
  final bg = light ? const Color(0xFFF4F3F0) : const Color(0xFF0E0E10);
  // карточки — полупрозрачные (стекло без размытия: дёшево даже в длинных списках)
  final card = light ? Colors.white.withValues(alpha: 0.62) : Colors.white.withValues(alpha: 0.075);
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
    popupMenuTheme: PopupMenuThemeData(color: light ? Colors.white : const Color(0xFF1E1E23)),
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
  );
}

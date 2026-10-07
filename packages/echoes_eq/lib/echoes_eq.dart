import 'package:flutter/services.dart';

/// Эквалайзер на iOS: 10 полос (32 Гц … 16 кГц, ±12 дБ) и предусиление. Сам звук обрабатывается в
/// нативной части (ios/Classes/EchoesEqPlugin.m) — меняется сразу, без перезапуска трека.
/// На других платформах и в тестах — тихо ничего не делает.
class EchoesEq {
  static const _ch = MethodChannel('echoes/eq');
  static const frequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  /// gains — 10 значений в дБ (−12…+12), preamp — общий уровень в дБ, enabled — вкл/выкл.
  static Future<void> apply({required List<double> gains, double preamp = 0, bool enabled = true}) async {
    try {
      await _ch.invokeMethod('set', {'gains': gains, 'preamp': preamp, 'enabled': enabled});
    } on MissingPluginException {
      // не iOS / тесты
    } on PlatformException {
      // нативная часть не смогла — без эквалайзера
    }
  }
}
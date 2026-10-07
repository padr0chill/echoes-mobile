import 'dart:async';

import 'package:echoes_mobile/i18n.dart';

/// Тесты ищут русские подписи, а язык «как в системе» на компьютере обычно английский — фиксируем русский.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  appLangSetting = 'ru';
  await testMain();
}

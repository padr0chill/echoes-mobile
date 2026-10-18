import 'dart:io';

import 'package:flutter/foundation.dart';

/// Журнал ошибок: последние 500 строк в памяти и файл в папке приложения (переживает перезапуск).
/// Ошибки по-прежнему можно «глотать», но теперь — с записью: в настройках журнал можно скопировать
/// и прислать разработчику.
class Log {
  Log._();
  static final Log instance = Log._();

  static const _max = 500;
  static const _maxFileBytes = 256 * 1024;

  final _lines = <String>[];
  File? _file;

  List<String> get lines => List.unmodifiable(_lines);

  /// Папка приложения известна — подхватить прошлый журнал и писать дальше в файл.
  void init(String dir) {
    try {
      final f = File('$dir/echoes_log.txt');
      if (f.existsSync()) {
        // слишком большой — оставить хвост
        if (f.lengthSync() > _maxFileBytes) {
          final keep = f.readAsLinesSync();
          f.writeAsStringSync('${keep.skip(keep.length - _max ~/ 2).join('\n')}\n');
        }
        _lines.addAll(f.readAsLinesSync().where((l) => l.isNotEmpty));
        if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
      }
      _file = f;
    } catch (_) {}
  }

  void w(String where, Object e, [StackTrace? st]) {
    final t = DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
    var line = '$t  $where: $e';
    if (st != null) {
      // первые строки стека — их хватает, чтобы найти место
      line += '\n${st.toString().split('\n').take(6).map((l) => '    $l').join('\n')}';
    }
    debugPrint(line);
    _lines.addAll(line.split('\n'));
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  void clear() {
    _lines.clear();
    try {
      _file?.writeAsStringSync('');
    } catch (_) {}
  }
}

final log = Log.instance;

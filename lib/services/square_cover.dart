import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Чистая квадратная обложка для видео YouTube: превью в высоком качестве (1280×720), автоматически
/// обрезаются однотонные полосы по краям (чёрные «леттербокс»/«пилларбокс»), вырезается квадрат по центру
/// содержимого и сохраняется на телефоне (кэш, ≤ 720 px). Для экрана блокировки и больших обложек.
/// У треков SoundCloud / YouTube Music обложка и так квадратная — для них null.
class SquareCover {
  SquareCover._();
  static final SquareCover instance = SquareCover._();

  final _jobs = <String, Future<File?>>{};
  Directory? _dir;

  /// Нужна обрезка: видео YouTube без своей обложки или «обложка» — превью YouTube (i.ytimg.com, с полосами).
  bool needed(Track t) => (t.isYt && t.art == null) || (t.art?.contains('i.ytimg.com') ?? false);

  /// Видео, чьё превью обрезаем: из ссылки на превью или сам трек.
  static String videoOf(Track t) => RegExp(r'/vi(?:_webp)?/([\w-]{11})/').firstMatch(t.art ?? '')?.group(1) ?? t.id;

  /// Обрезанные обложки — заранее (текущий и следующие треки очереди): в плеере сразу чистый квадрат.
  void prefetch(Iterable<Track> list) {
    for (final t in list) {
      if (needed(t)) get(t);
    }
  }

  /// Папка кэша — заранее (чтобы ready() работал с первого кадра).
  Future<void> init() async {
    try {
      final base = await getTemporaryDirectory();
      _dir ??= Directory('${base.path}/square_covers')..createSync(recursive: true);
    } catch (_) {}
  }

  Future<File?> get(Track t) {
    if (!needed(t)) return Future.value(null);
    return _jobs.putIfAbsent(videoOf(t), () => _make(t).catchError((_) => null));
  }

  /// Уже готовая (без ожидания) — чтобы не мигала заглушка.
  File? ready(Track t) {
    final d = _dir;
    if (d == null || !needed(t)) return null;
    final f = File('${d.path}/${videoOf(t)}.png');
    return f.existsSync() ? f : null;
  }

  // ── маленькие обложки для списков: та же обрезка по содержимому, но по превью 480×360 (быстро, ~25 КБ) ──
  final _small = <String, Future<File?>>{};
  int _running = 0;
  final _waiters = <Completer<void>>[];

  /// Не больше 4 обложек за раз — листание не тормозит.
  Future<T> _limit<T>(Future<T> Function() f) async {
    while (_running >= 4) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _running++;
    try {
      return await f();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }

  /// Готовая обложка для списка (большая тоже подходит) — без ожидания.
  File? readySmall(Track t) {
    final big = ready(t);
    if (big != null) return big;
    final d = _dir;
    if (d == null || !needed(t)) return null;
    final f = File('${d.path}/${videoOf(t)}_s.png');
    return f.existsSync() ? f : null;
  }

  Future<File?> getSmall(Track t) {
    if (!needed(t)) return Future.value(null);
    final ready = readySmall(t);
    if (ready != null) return Future.value(ready);
    return _small.putIfAbsent(videoOf(t), () => _limit(() => _makeSmall(t)).catchError((_) => null));
  }

  /// Обложки списка — заранее (открыли плейлист): при листании уже без полос.
  void prefetchSmall(Iterable<Track> list, {int max = 120}) {
    var n = 0;
    for (final t in list) {
      if (n >= max) break;
      if (needed(t) && readySmall(t) == null) {
        getSmall(t);
        n++;
      }
    }
  }

  Future<File?> _makeSmall(Track t) async {
    final base = await getTemporaryDirectory();
    final d = _dir ??= Directory('${base.path}/square_covers')..createSync(recursive: true);
    final vid = videoOf(t);
    final out = File('${d.path}/${vid}_s.png');
    if (out.existsSync()) return out;
    final r =
        await http.get(Uri.parse('https://i.ytimg.com/vi/$vid/hqdefault.jpg')).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200 || r.bodyBytes.length < 1500) return null;
    final png = await squarePng(r.bodyBytes, maxSide: 240);
    if (png == null) return null;
    await out.writeAsBytes(png, flush: true);
    return out;
  }

  Future<File?> _make(Track t) async {
    final base = await getTemporaryDirectory();
    final d = _dir ??= Directory('${base.path}/square_covers')..createSync(recursive: true);
    final vid = videoOf(t);
    final out = File('${d.path}/$vid.png');
    if (out.existsSync()) return out;
    Uint8List? bytes;
    // maxres бывает не у всех видео (тогда YouTube отдаёт заглушку 120×90) — тогда sd/hq
    for (final name in ['maxresdefault', 'sddefault', 'hqdefault']) {
      try {
        final r =
            await http.get(Uri.parse('https://i.ytimg.com/vi/$vid/$name.jpg')).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200 && r.bodyBytes.length > 3000) {
          bytes = r.bodyBytes;
          break;
        }
      } catch (_) {}
    }
    if (bytes == null) return null;
    final png = await squarePng(bytes);
    if (png == null) return null;
    await out.writeAsBytes(png, flush: true);
    return out;
  }

  /// Картинка → PNG квадрат без полос (≤ 720 px). Отдельно — для тестов.
  static Future<Uint8List?> squarePng(Uint8List bytes, {int maxSide = 720, bool darkOnly = false}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    try {
      final rect = await contentRect(img, darkOnly: darkOnly);
      final side = rect.width < rect.height ? rect.width : rect.height;
      final src = ui.Rect.fromCenter(center: rect.center, width: side, height: side);
      final outSide = side.round().clamp(64, maxSide);
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawImageRect(
        img,
        src,
        ui.Rect.fromLTWH(0, 0, outSide.toDouble(), outSide.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final pic = rec.endRecording();
      final sq = await pic.toImage(outSide, outSide);
      pic.dispose();
      final data = await sq.toByteData(format: ui.ImageByteFormat.png);
      sq.dispose();
      return data?.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  }

  /// Область без однотонных полос по краям: строки/столбцы, почти одинаковые по цвету (полосы —
  /// чёрные или любого сплошного цвета), отрезаются с каждой стороны.
  /// darkOnly — срезать только почти чёрные полосы (у обложек светлая рамка — часть рисунка).
  static Future<ui.Rect> contentRect(ui.Image img, {bool darkOnly = false}) async {
    final w = img.width, h = img.height;
    final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    double lum(int x, int y) {
      final i = (y * w + x) * 4;
      return 0.299 * data.getUint8(i) + 0.587 * data.getUint8(i + 1) + 0.114 * data.getUint8(i + 2);
    }

    // строка/столбец «полоса», если разброс яркости мал (проверяем каждый 4-й пиксель)
    bool flatRow(int y) {
      var mn = 255.0, mx = 0.0;
      for (var x = 0; x < w; x += 4) {
        final l = lum(x, y);
        if (l < mn) mn = l;
        if (l > mx) mx = l;
      }
      return mx - mn < 18 && (!darkOnly || mx < 16);
    }

    bool flatCol(int x) {
      var mn = 255.0, mx = 0.0;
      for (var y = 0; y < h; y += 4) {
        final l = lum(x, y);
        if (l < mn) mn = l;
        if (l > mx) mx = l;
      }
      return mx - mn < 18 && (!darkOnly || mx < 16);
    }

    // у обложек — не больше 15 % с края (дальше уже рисунок), у кадров видео — до трети
    final lim = darkOnly ? 0.15 : 1 / 3;
    var top = 0, bottom = h - 1, left = 0, right = w - 1;
    while (top < h * lim && flatRow(top)) {
      top++;
    }
    while (bottom > h * (1 - lim) && flatRow(bottom)) {
      bottom--;
    }
    while (left < w * lim && flatCol(left)) {
      left++;
    }
    while (right > w * (1 - lim) && flatCol(right)) {
      right--;
    }
    return ui.Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
  }
}

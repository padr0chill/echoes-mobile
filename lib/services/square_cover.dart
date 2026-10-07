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

  bool needed(Track t) => t.isYt && t.art == null;

  /// Папка кэша — заранее (чтобы ready() работал с первого кадра).
  Future<void> init() async {
    try {
      final base = await getTemporaryDirectory();
      _dir ??= Directory('${base.path}/square_covers')..createSync(recursive: true);
    } catch (_) {}
  }

  Future<File?> get(Track t) {
    if (!needed(t)) return Future.value(null);
    return _jobs.putIfAbsent(t.id, () => _make(t).catchError((_) => null));
  }

  /// Уже готовая (без ожидания) — чтобы не мигала заглушка.
  File? ready(Track t) {
    final d = _dir;
    if (d == null || !needed(t)) return null;
    final f = File('${d.path}/${t.id}.png');
    return f.existsSync() ? f : null;
  }

  Future<File?> _make(Track t) async {
    final base = await getTemporaryDirectory();
    final d = _dir ??= Directory('${base.path}/square_covers')..createSync(recursive: true);
    final out = File('${d.path}/${t.id}.png');
    if (out.existsSync()) return out;
    Uint8List? bytes;
    // maxres бывает не у всех видео (тогда YouTube отдаёт заглушку 120×90) — тогда sd/hq
    for (final name in ['maxresdefault', 'sddefault', 'hqdefault']) {
      try {
        final r =
            await http.get(Uri.parse('https://i.ytimg.com/vi/${t.id}/$name.jpg')).timeout(const Duration(seconds: 8));
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
  static Future<Uint8List?> squarePng(Uint8List bytes, {int maxSide = 720}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    try {
      final rect = await contentRect(img);
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
  static Future<ui.Rect> contentRect(ui.Image img) async {
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
      return mx - mn < 18;
    }

    bool flatCol(int x) {
      var mn = 255.0, mx = 0.0;
      for (var y = 0; y < h; y += 4) {
        final l = lum(x, y);
        if (l < mn) mn = l;
        if (l > mx) mx = l;
      }
      return mx - mn < 18;
    }

    var top = 0, bottom = h - 1, left = 0, right = w - 1;
    while (top < h ~/ 3 && flatRow(top)) {
      top++;
    }
    while (bottom > h * 2 ~/ 3 && flatRow(bottom)) {
      bottom--;
    }
    while (left < w ~/ 3 && flatCol(left)) {
      left++;
    }
    while (right > w * 2 ~/ 3 && flatCol(right)) {
      right--;
    }
    return ui.Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
  }
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Размытая обложка для фона — гладкая, без «пикселей». Размывается ОДИН раз на картинку (обложка 96 px →
/// гауссово размытие → готовая картинка в памяти), дальше просто растягивается: размытая картинка не
/// имеет резких краёв, поэтому растяжение не даёт квадратиков, а видеокарта не пересчитывает размытие
/// каждый кадр. Последние 12 — в памяти.
class BlurredCover extends StatefulWidget {
  final ImageProvider image;
  final String cacheKey;
  final Widget Function()? fallback;
  final double strength; // сила размытия 0…1 (1 — как раньше: мягкое пятно цвета)
  const BlurredCover({super.key, required this.image, required this.cacheKey, this.fallback, this.strength = 1});

  String get _key => '$cacheKey@${(strength * 20).round()}';

  static final _cache = <String, ui.Image>{}; // по порядку добавления — старые удаляются первыми

  @override
  State<BlurredCover> createState() => _BlurredCoverState();
}

class _BlurredCoverState extends State<BlurredCover> {
  ui.Image? _img;
  ImageStream? _stream;
  ImageStreamListener? _l;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BlurredCover old) {
    super.didUpdateWidget(old);
    if (old._key != widget._key) _load();
  }

  void _load() {
    _stop();
    final c = BlurredCover._cache[widget._key];
    if (c != null) {
      _img = c;
      return;
    }
    final full = widget.strength >= 0.98;
    // слабое размытие — картинка покрупнее (иначе всё равно «мыло»), сильное — маленькая (дёшево)
    final side = full ? 96 : (widget.strength < 0.05 ? 1080 : 540);
    _stream = ResizeImage(widget.image, width: side, height: side, policy: ResizeImagePolicy.fit)
        .resolve(ImageConfiguration.empty);
    _l = ImageStreamListener((info, _) {
      final key = widget._key;
      (full ? _blur(info.image) : _soft(info.image, widget.strength)).then((b) {
        BlurredCover._cache[key] = b;
        if (BlurredCover._cache.length > 12) BlurredCover._cache.remove(BlurredCover._cache.keys.first);
        if (mounted && widget.cacheKey == key) setState(() => _img = b);
      });
      _stop();
    }, onError: (_, __) => _stop());
    _stream!.addListener(_l!);
  }

  void _stop() {
    if (_stream != null && _l != null) _stream!.removeListener(_l!);
    _stream = null;
    _l = null;
  }

  /// Своя сила размытия: картинка с исходными пропорциями (≤ 1080 px), размытие ~0…28 px.
  static Future<ui.Image> _soft(ui.Image src, double k) {
    final w = src.width.toDouble(), h = src.height.toDouble();
    final sigma = k * 28 * (w > h ? w : h) / 540;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final r = Rect.fromLTWH(0, 0, w, h);
    if (sigma > 0.3) {
      canvas.saveLayer(
          r, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp));
    }
    canvas.drawImageRect(src, r, r, Paint()..filterQuality = FilterQuality.medium);
    if (sigma > 0.3) canvas.restore();
    final pic = rec.endRecording();
    final img = pic.toImageSync(src.width, src.height);
    pic.dispose();
    return Future.value(img);
  }

  /// 96 px → размытие с запасом по краям (края не темнеют) → 64×64 мягкая картинка.
  static Future<ui.Image> _blur(ui.Image src) {
    const out = 64.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final w = src.width.toDouble(), h = src.height.toDouble();
    final side = w < h ? w : h;
    final srcRect = Rect.fromCenter(center: Offset(w / 2, h / 2), width: side, height: side);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, out, out),
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6, tileMode: TileMode.clamp));
    canvas.drawImageRect(
        src, srcRect, const Rect.fromLTWH(-8, -8, out + 16, out + 16), Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    final pic = rec.endRecording();
    final img = pic.toImageSync(out.toInt(), out.toInt());
    pic.dispose();
    return Future.value(img);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    if (img == null) return widget.fallback?.call() ?? const SizedBox();
    return RawImage(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
  }
}

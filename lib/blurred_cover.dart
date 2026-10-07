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
  const BlurredCover({super.key, required this.image, required this.cacheKey, this.fallback});

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
    if (old.cacheKey != widget.cacheKey) _load();
  }

  void _load() {
    _stop();
    final c = BlurredCover._cache[widget.cacheKey];
    if (c != null) {
      _img = c;
      return;
    }
    _stream = ResizeImage(widget.image, width: 96, height: 96, policy: ResizeImagePolicy.fit)
        .resolve(ImageConfiguration.empty);
    _l = ImageStreamListener((info, _) {
      final key = widget.cacheKey;
      _blur(info.image).then((b) {
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

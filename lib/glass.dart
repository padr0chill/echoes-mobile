import 'dart:ui';

import 'package:flutter/material.dart';

import 'services/audio.dart';
import 'services/store.dart';
import 'ui.dart';
import 'widgets.dart';

/// «Жидкое стекло» (как в новых iOS): размытие того, что под панелью, полупрозрачная заливка,
/// светлая грань и блик сверху. Использовать на панелях и кнопках — не в длинных списках (дорого).
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double tint; // плотность заливки 0..1
  final bool shadow;

  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding,
    this.blur = 24,
    this.tint = 1,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final light = Store.instance.light;
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: light ? 0.10 : 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10))
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              // заливка: светлее сверху (блик), прозрачнее снизу
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: light
                    ? [Colors.white.withValues(alpha: 0.72 * tint), Colors.white.withValues(alpha: 0.48 * tint)]
                    : [Colors.white.withValues(alpha: 0.16 * tint), Colors.white.withValues(alpha: 0.05 * tint)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: light ? 0.7 : 0.22), width: 1),
            ),
            child: Stack(children: [
              // тонкий блик по верхней кромке
              Positioned(
                left: radius * 0.6,
                right: radius * 0.6,
                top: 0,
                height: 1.2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: light ? 0.9 : 0.55),
                      Colors.white.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
              child,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Круглая стеклянная кнопка-значок.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  final Color? color;

  const GlassIconButton({super.key, required this.icon, this.onTap, this.size = 44, this.tooltip, this.color});

  @override
  Widget build(BuildContext context) {
    final s = context.u(size);
    final b = Glass(
      radius: s / 2,
      shadow: false,
      child: SizedBox(
        width: s,
        height: s,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: s * 0.5, color: color),
          ),
        ),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

/// Фон-«атмосфера»: размытая обложка текущего трека + оттенок акцента, как в Apple Music.
/// Перерисовывается только при смене трека (RepaintBoundary), поэтому стекло поверх неё — дёшево.
class Ambient extends StatelessWidget {
  final Widget child;
  final String? image; // своя картинка (страница исполнителя); иначе — обложка играющего трека

  const Ambient({super.key, required this.child, this.image});

  @override
  Widget build(BuildContext context) {
    final light = Store.instance.light;
    final base = light ? const Color(0xFFF2F1EE) : const Color(0xFF0B0B0E);
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: base),
      RepaintBoundary(
        child: ValueListenableBuilder<int>(
          valueListenable: audio.index,
          builder: (context, _, __) {
            final src = image ?? audio.current?.thumb;
            return Stack(fit: StackFit.expand, children: [
              // пятна акцента — видны и без обложки
              Positioned(
                left: -120,
                top: -140,
                child: _Blob(color: context.accent.withValues(alpha: light ? 0.30 : 0.35), size: 380),
              ),
              Positioned(
                right: -160,
                bottom: 80,
                child: _Blob(
                  color: HSLColor.fromColor(context.accent)
                      .withHue((HSLColor.fromColor(context.accent).hue + 300) % 360)
                      .toColor()
                      .withValues(alpha: light ? 0.22 : 0.28),
                  size: 420,
                ),
              ),
              if (src != null && Cover.debugImage == null)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: ImageFiltered(
                    key: ValueKey(src),
                    imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.decal),
                    child: Opacity(
                      opacity: light ? 0.35 : 0.55,
                      child: Image.network(src,
                          fit: BoxFit.cover, cacheWidth: 96, errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                  ),
                ),
              if (src != null && Cover.debugImage != null && audio.current != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.decal),
                  child: Opacity(
                    opacity: light ? 0.35 : 0.55,
                    child: Image(image: Cover.debugImage!(audio.current!), fit: BoxFit.cover),
                  ),
                ),
              Container(color: base.withValues(alpha: light ? 0.35 : 0.45)),
            ]);
          },
        ),
      ),
      child,
    ]);
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

/// Шторка снизу в стекле.
Future<T?> showGlassSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + MediaQuery.paddingOf(ctx).bottom),
      child: Glass(
        radius: 30,
        tint: 1.6,
        child: SafeArea(top: false, bottom: false, child: builder(ctx)),
      ),
    ),
  );
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/store.dart';
import '../services/wave.dart';
import '../ui.dart';
import '../widgets.dart';
import 'artist_screen.dart';

/// «Моя волна»: живое сияние на весь экран, по центру — кнопка запуска или текущий трек.
/// Настроения спрятаны в отдельную стеклянную кнопку «Настроить».
class WaveScreen extends StatelessWidget {
  const WaveScreen({super.key});

  static const _moodIcons = {
    'Энергичное': Icons.bolt_rounded,
    'Спокойное': Icons.spa_rounded,
    'Грустное': Icons.water_drop_rounded,
    'Тренировка': Icons.fitness_center_rounded,
    'Для сна': Icons.bedtime_rounded,
    'Русский рэп': Icons.mic_rounded,
  };

  void _tune(BuildContext context) {
    final w = Wave.instance;
    showGlassSheet(context, (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Настроить волну', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        SizedBox(height: ctx.u(4)),
        Text('Выберите настроение — волна сразу перестроится',
            style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
        SizedBox(height: ctx.u(16)),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: ctx.u(10),
          crossAxisSpacing: ctx.u(10),
          childAspectRatio: 2.6 / MediaQuery.textScalerOf(ctx).scale(1).clamp(1.0, 1.6),
          children: [
            _MoodTile(
              icon: Icons.all_inclusive_rounded,
              label: 'Под вас',
              selected: w.active && w.mood == null,
              onTap: () {
                Navigator.pop(ctx);
                w.start();
              },
            ),
            for (final m in Wave.moods.keys)
              _MoodTile(
                icon: _moodIcons[m] ?? Icons.music_note_rounded,
                label: m,
                selected: w.active && w.mood == m,
                onTap: () {
                  Navigator.pop(ctx);
                  w.start(mood: m);
                },
              ),
          ],
        ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = Wave.instance;
    return Stack(children: [
      const Positioned.fill(child: _Aura()),
      SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([w, audio.index, Store.instance]),
          builder: (context, _) {
            final active = w.active;
            final t = active ? audio.current : null;
            final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.65);
            return LayoutBuilder(builder: (context, box) {
              return SingleChildScrollView(
                padding: EdgeInsets.only(bottom: context.u(200)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - context.u(200))),
                  child: Column(children: [
                    // шапка: заголовок + кнопка настроек
                    Padding(
                      padding: EdgeInsets.fromLTRB(context.u(16), context.u(14), context.u(16), 0),
                      child: Row(children: [
                        const Expanded(
                          child: Text('Моя волна',
                              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        ),
                        _TuneButton(onTap: () => _tune(context)),
                      ]),
                    ),
                    SizedBox(height: context.u(6)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: active
                            ? Glass(
                                radius: 99,
                                blur: 16,
                                shadow: false,
                                padding: EdgeInsets.symmetric(horizontal: context.u(12), vertical: context.u(6)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(
                                      w.mood != null
                                          ? (_moodIcons[w.mood] ?? Icons.tune_rounded)
                                          : Icons.all_inclusive_rounded,
                                      size: context.u(16),
                                      color: context.accent),
                                  SizedBox(width: context.u(6)),
                                  Text(w.mood ?? 'Под ваш вкус', style: const TextStyle(fontWeight: FontWeight.w700)),
                                ]),
                              )
                            : Text('Бесконечный поток музыки под вас', style: TextStyle(color: dim)),
                      ),
                    ),
                    SizedBox(height: context.u(28)),
                    if (t == null)
                      _StartButton(loading: w.loading, onTap: () => w.loading ? null : w.start())
                    else
                      _NowPlaying(track: t),
                    if (w.error != null)
                      Padding(
                        padding: EdgeInsets.all(context.u(16)),
                        child: Glass(
                          radius: context.u(16),
                          padding: EdgeInsets.all(context.u(12)),
                          child: Text(w.error!,
                              textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80))),
                        ),
                      ),
                    if (!active && !w.loading) ...[
                      SizedBox(height: context.u(26)),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: context.u(8),
                        runSpacing: context.u(8),
                        children: [
                          for (final m in Wave.moods.keys.take(3))
                            _QuickMood(
                                icon: _moodIcons[m] ?? Icons.music_note_rounded,
                                label: m,
                                onTap: () => w.start(mood: m)),
                          _QuickMood(icon: Icons.more_horiz_rounded, label: 'Ещё', onTap: () => _tune(context)),
                        ],
                      ),
                    ],
                  ]),
                ),
              );
            });
          },
        ),
      ),
    ]);
  }
}

/// Капсула «Настроить» в правом верхнем углу.
class _TuneButton extends StatelessWidget {
  final VoidCallback onTap;
  const _TuneButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Настроить волну',
      child: GestureDetector(
        onTap: onTap,
        child: Glass(
          radius: 99,
          tint: 1.2,
          padding: EdgeInsets.symmetric(horizontal: context.u(14), vertical: context.u(9)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune_rounded, size: context.u(18)),
            SizedBox(width: context.u(6)),
            const Text('Настроить', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// Большая стеклянная кнопка запуска, «дышит» кольцом акцента.
class _StartButton extends StatefulWidget {
  final bool loading;
  final VoidCallback onTap;
  const _StartButton({required this.loading, required this.onTap});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = math.min(context.u(210), MediaQuery.sizeOf(context).width * 0.56);
    final a = context.accent;
    return Column(children: [
      GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final v = Curves.easeInOut.transform(_c.value);
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: a.withValues(alpha: 0.25 + 0.25 * v), blurRadius: size * (0.25 + 0.15 * v))
                ],
              ),
              child: child,
            );
          },
          child: Glass(
            radius: size / 2,
            tint: 1.1,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: widget.loading
                    ? SizedBox(
                        width: size * 0.26,
                        height: size * 0.26,
                        child: CircularProgressIndicator(strokeWidth: 3, color: a),
                      )
                    : Icon(Icons.play_arrow_rounded, size: size * 0.42, color: a),
              ),
            ),
          ),
        ),
      ),
      SizedBox(height: context.u(18)),
      Text(widget.loading ? 'Собираю волну…' : 'Запустить волну',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
    ]);
  }
}

/// Текущий трек волны: обложка с сиянием, название, исполнитель (ссылка), стеклянная панель управления.
class _NowPlaying extends StatelessWidget {
  final Track track;
  const _NowPlaying({required this.track});

  @override
  Widget build(BuildContext context) {
    final t = track;
    final size = math.min(context.u(250), MediaQuery.sizeOf(context).width * 0.66);
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7);
    final liked = Store.instance.isLiked(t);
    return Column(children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: c),
        ),
        child: Container(
          key: ValueKey(t.id),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.u(28)),
            boxShadow: [
              BoxShadow(
                  color: context.accent.withValues(alpha: 0.35), blurRadius: size * 0.3, offset: Offset(0, size * 0.06))
            ],
          ),
          child: Cover(track: t, size: size, radius: context.u(28), big: true),
        ),
      ),
      SizedBox(height: context.u(20)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: context.u(24)),
        child: Text(t.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      ),
      SizedBox(height: context.u(2)),
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openArtist(context, t),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.u(8), vertical: context.u(2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: dim, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded, size: context.u(18), color: dim),
          ]),
        ),
      ),
      SizedBox(height: context.u(18)),
      Glass(
        radius: 99,
        tint: 1.2,
        padding: EdgeInsets.symmetric(horizontal: context.u(10), vertical: context.u(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GlassIconButton(
            icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: liked ? context.accent : null,
            tooltip: 'Нравится',
            onTap: () => Store.instance.toggleLike(t),
          ),
          SizedBox(width: context.u(10)),
          PlayPauseButton(size: context.u(60), filled: true),
          SizedBox(width: context.u(10)),
          GlassIconButton(icon: Icons.skip_next_rounded, tooltip: 'Пропустить', onTap: audio.skipToNext),
          SizedBox(width: context.u(10)),
          GlassIconButton(icon: Icons.stop_rounded, tooltip: 'Остановить волну', onTap: Wave.instance.stop),
        ]),
      ),
    ]);
  }
}

class _MoodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MoodTile({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Material(
      color: selected ? a.withValues(alpha: 0.28) : Colors.white.withValues(alpha: Store.instance.light ? 0.5 : 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.u(18)),
        side: BorderSide(color: selected ? a : Colors.white.withValues(alpha: 0.18)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.u(18)),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.u(12)),
          child: Row(children: [
            Icon(icon, color: a, size: context.u(22)),
            SizedBox(width: context.u(8)),
            Expanded(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _QuickMood extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickMood({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Glass(
        radius: 99,
        blur: 16,
        shadow: false,
        padding: EdgeInsets.symmetric(horizontal: context.u(12), vertical: context.u(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: context.u(16), color: context.accent),
          SizedBox(width: context.u(6)),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Сияние на фоне: несколько мягких пятен акцента медленно плавают; когда играет — быстрее и ярче.
class _Aura extends StatefulWidget {
  const _Aura();

  @override
  State<_Aura> createState() => _AuraState();
}

class _AuraState extends State<_Aura> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  double _phase = 0;
  double _last = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final h = HSLColor.fromColor(a);
    final colors = [
      a,
      h.withHue((h.hue + 45) % 360).toColor(),
      h.withHue((h.hue + 300) % 360).toColor(),
    ];
    return IgnorePointer(
      child: RepaintBoundary(
        child: StreamBuilder<bool>(
          stream: audio.player.playingStream,
          builder: (context, snap) {
            final playing = (snap.data ?? false) && Wave.instance.active;
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                // фаза копится: при игре течёт втрое быстрее, без скачков
                var d = _c.value - _last;
                if (d < 0) d += 1;
                _last = _c.value;
                _phase += d * (playing ? 3 : 1);
                return CustomPaint(painter: _AuraPainter(_phase * 2 * math.pi, colors, playing ? 0.55 : 0.38));
              },
            );
          },
        ),
      ),
    );
  }
}

class _AuraPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  final double strength;
  _AuraPainter(this.t, this.colors, this.strength);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.max(size.width, size.height);
    final blobs = [
      (Offset(0.30 + 0.18 * math.sin(t), 0.28 + 0.10 * math.cos(t * 1.3)), 0.62, colors[0]),
      (Offset(0.75 + 0.15 * math.cos(t * 0.8), 0.40 + 0.14 * math.sin(t * 1.1)), 0.52, colors[1]),
      (Offset(0.50 + 0.22 * math.sin(t * 0.6 + 2), 0.62 + 0.10 * math.cos(t * 0.9)), 0.58, colors[2]),
    ];
    for (final (o, r, c) in blobs) {
      final center = Offset(o.dx * size.width, o.dy * size.height);
      final radius = r * s * 0.6;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [c.withValues(alpha: strength), c.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuraPainter old) => old.t != t || old.strength != strength || old.colors != colors;
}

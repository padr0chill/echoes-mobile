import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/audio.dart';
import '../services/wave.dart';
import '../ui.dart';
import '../widgets.dart';

/// «Моя волна» — как в ECHOES: большой живой круг, кнопка запуска и настроения.
class WaveScreen extends StatelessWidget {
  const WaveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w = Wave.instance;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([w, audio.index]),
        builder: (context, _) {
          final active = w.active;
          final t = active ? audio.current : null;
          return ListView(
            padding: EdgeInsets.only(bottom: context.u(130)),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(16), 0),
                child: const Text('Моя волна', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(4)),
                child: Text(
                  active
                      ? (w.mood != null ? 'Настроение: ${w.mood}' : 'Похожее на то, что вы любите')
                      : 'Бесконечный поток музыки под вас — по лайкам и истории',
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6)),
                ),
              ),
              SizedBox(height: context.u(18)),
              Center(
                child: GestureDetector(
                  onTap: () {
                    if (w.loading) return;
                    if (active) {
                      audio.player.playing ? audio.pause() : audio.play();
                    } else {
                      w.start();
                    }
                  },
                  child: _Orb(size: math.min(context.u(260), MediaQuery.sizeOf(context).width * 0.72), active: active),
                ),
              ),
              SizedBox(height: context.u(16)),
              Center(
                child: w.loading
                    ? Text('Собираю волну…', style: TextStyle(color: context.accent))
                    : t != null
                        ? Column(children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            Text(t.artist,
                                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
                          ])
                        : FilledButton.icon(
                            onPressed: () => w.start(),
                            icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                            label: const Text('Запустить волну', style: TextStyle(color: Colors.black)),
                          ),
              ),
              if (w.error != null)
                Padding(
                  padding: EdgeInsets.all(context.u(12)),
                  child: Text(w.error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80))),
                ),
              if (active)
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: context.u(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton.filledTonal(
                        tooltip: 'Пропустить',
                        onPressed: audio.skipToNext,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                      SizedBox(width: context.u(12)),
                      IconButton.filledTonal(
                        tooltip: 'Остановить волну',
                        onPressed: w.stop,
                        icon: const Icon(Icons.stop_rounded),
                      ),
                    ]),
                  ),
                ),
              const SectionTitle('Настроение'),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                child: Wrap(spacing: context.u(8), runSpacing: context.u(8), children: [
                  for (final m in Wave.moods.keys)
                    ChoiceChip(
                      label: Text(m),
                      selected: active && w.mood == m,
                      onSelected: (_) => w.loading ? null : w.start(mood: m),
                    ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Живой круг: переливающийся градиент акцента, медленно вращается; пока играет — «дышит».
class _Orb extends StatefulWidget {
  final double size;
  final bool active;
  const _Orb({required this.size, required this.active});

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final b = HSLColor.fromColor(a).withHue((HSLColor.fromColor(a).hue + 40) % 360).toColor();
    final c = HSLColor.fromColor(a).withHue((HSLColor.fromColor(a).hue + 320) % 360).toColor();
    return StreamBuilder<bool>(
      stream: audio.player.playingStream,
      builder: (context, snap) {
        final playing = widget.active && (snap.data ?? false);
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 * math.pi;
            final breathe = playing ? 1 + 0.035 * math.sin(t * 6) : 1.0;
            return RepaintBoundary(
              child: Transform.scale(
                scale: breathe,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      transform: GradientRotation(t),
                      colors: [a, b, c, a],
                    ),
                    boxShadow: [BoxShadow(color: a.withValues(alpha: 0.45), blurRadius: widget.size * 0.25)],
                  ),
                  child: Container(
                    margin: EdgeInsets.all(widget.size * 0.06),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        Colors.white.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.15),
                      ], center: const Alignment(-0.3, -0.4), radius: 1.1),
                    ),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: widget.size * 0.28,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

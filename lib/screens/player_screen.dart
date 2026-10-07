import 'dart:ui';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/audio.dart';
import '../services/lyrics.dart';
import '../services/store.dart';
import '../ui.dart';
import '../widgets.dart';
import 'artist_screen.dart';

/// Полный плеер: размытая обложка фоном, обложка, название, перемотка, кнопки; текст песни и очередь.
/// На широком экране (iPad, поворот) — обложка слева, управление справа.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _lyrics = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: audio.index,
      builder: (context, _, __) {
        final t = audio.current;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [
            if (t != null) _Backdrop(track: t),
            SafeArea(
              child: LayoutBuilder(builder: (context, box) {
                final wide = box.maxWidth > box.maxHeight * 1.05;
                final header = _Header(
                  lyrics: _lyrics,
                  onLyrics: () => setState(() => _lyrics = !_lyrics),
                );
                final main = _lyrics && t != null
                    ? _LyricsView(track: t)
                    : Center(
                        child: Padding(
                          padding: EdgeInsets.all(context.u(12)),
                          child: Hero(
                            tag: 'cover',
                            child: Cover(
                              track: t,
                              size: (wide ? box.maxHeight * 0.62 : box.maxWidth - context.u(56))
                                  .clamp(120.0, 520.0)
                                  .toDouble(),
                              radius: context.u(18),
                              big: true,
                            ),
                          ),
                        ),
                      );
                final controls = _Controls(track: t);
                if (wide) {
                  return Column(children: [
                    header,
                    Expanded(
                      child: Row(children: [
                        Expanded(child: main),
                        Expanded(child: Center(child: SingleChildScrollView(child: controls))),
                      ]),
                    ),
                  ]);
                }
                return Column(children: [header, Expanded(child: main), controls, SizedBox(height: context.u(12))]);
              }),
            ),
          ]),
        );
      },
    );
  }
}

class _Backdrop extends StatelessWidget {
  final Track track;
  const _Backdrop({required this.track});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Cover.debugImage != null
            ? Image(image: Cover.debugImage!(track), fit: BoxFit.cover)
            : Image.network(track.thumb,
                fit: BoxFit.cover, cacheWidth: 120, errorBuilder: (_, __, ___) => const SizedBox()),
      ),
      Container(color: Colors.black.withValues(alpha: 0.55)),
    ]);
  }
}

class _Header extends StatelessWidget {
  final bool lyrics;
  final VoidCallback onLyrics;
  const _Header({required this.lyrics, required this.onLyrics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.u(8)),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Текст песни',
          icon: Icon(Icons.lyrics_rounded, color: lyrics ? context.accent : Colors.white),
          onPressed: onLyrics,
        ),
        IconButton(
          tooltip: 'Очередь',
          icon: const Icon(Icons.queue_music_rounded, color: Colors.white),
          onPressed: () => _showQueue(context),
        ),
      ]),
    );
  }
}

class _Controls extends StatelessWidget {
  final Track? track;
  const _Controls({required this.track});

  @override
  Widget build(BuildContext context) {
    final t = track;
    const white = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.6);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.u(24)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t?.title ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: white, fontSize: 22, fontWeight: FontWeight.w800)),
              SizedBox(height: context.u(2)),
              GestureDetector(
                onTap: t == null ? null : () => openArtist(context, t),
                child: Text(t?.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: dim,
                        fontSize: 16,
                        decoration: TextDecoration.underline,
                        decorationColor: dim.withValues(alpha: 0.4))),
              ),
            ]),
          ),
          if (t != null)
            ListenableBuilder(
              listenable: Store.instance,
              builder: (context, _) => IconButton(
                icon: Icon(Store.instance.isLiked(t) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: Store.instance.isLiked(t) ? context.accent : white, size: 28),
                onPressed: () => Store.instance.toggleLike(t),
              ),
            ),
        ]),
        SizedBox(height: context.u(10)),
        const _Seek(),
        ValueListenableBuilder<String?>(
          valueListenable: audio.error,
          builder: (context, e, _) => e == null
              ? const SizedBox(height: 4)
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(e, style: const TextStyle(color: Color(0xFFFF8A80))),
                ),
        ),
        SizedBox(height: context.u(6)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          ValueListenableBuilder<bool>(
            valueListenable: audio.shuffle,
            builder: (context, on, _) => IconButton(
              icon: Icon(Icons.shuffle_rounded, color: on ? context.accent : dim),
              onPressed: audio.toggleShuffle,
            ),
          ),
          IconButton(
            iconSize: context.u(40),
            icon: const Icon(Icons.skip_previous_rounded, color: white),
            onPressed: audio.skipToPrevious,
          ),
          const PlayPauseButton(size: 72, filled: true),
          IconButton(
            iconSize: context.u(40),
            icon: const Icon(Icons.skip_next_rounded, color: white),
            onPressed: audio.skipToNext,
          ),
          ValueListenableBuilder<RepeatState>(
            valueListenable: audio.repeat,
            builder: (context, r, _) => IconButton(
              icon: Icon(r == RepeatState.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: r == RepeatState.off ? dim : context.accent),
              onPressed: audio.cycleRepeat,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Seek extends StatefulWidget {
  const _Seek();

  @override
  State<_Seek> createState() => _SeekState();
}

class _SeekState extends State<_Seek> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.6);
    return StreamBuilder<Duration>(
      stream: audio.player.positionStream,
      builder: (context, snap) {
        final total = audio.player.duration ?? audio.current?.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble().clamp(1.0, double.infinity);
        final v = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
        return Column(children: [
          Slider(
            value: v,
            max: max,
            onChanged: (x) => setState(() => _drag = x),
            onChangeEnd: (x) {
              audio.seek(Duration(milliseconds: x.round()));
              setState(() => _drag = null);
            },
          ),
          SizedBox(height: context.u(6)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(fmtDuration(Duration(milliseconds: v.round())), style: TextStyle(color: dim, fontSize: 12)),
            Text(fmtDuration(total), style: TextStyle(color: dim, fontSize: 12)),
          ]),
        ]);
      },
    );
  }
}

/// Текст песни: синхронный — текущая строка крупно и по центру, щелчок по строке — перемотка.
class _LyricsView extends StatefulWidget {
  final Track track;
  const _LyricsView({required this.track});

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  late Future<Lyrics?> _f;
  final _sc = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _f = LyricsService.instance.get(widget.track);
  }

  @override
  void didUpdateWidget(covariant _LyricsView old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) {
      _f = LyricsService.instance.get(widget.track);
      _active = -1;
      _keys.clear();
    }
  }

  void _follow(int i) {
    if (i == _active) return;
    _active = i;
    final ctx = _keys[i]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.4, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Lyrics?>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: context.accent));
        }
        final ly = snap.data;
        if (ly == null || ly.lines.isEmpty) {
          return const Center(child: Text('Текст не найден', style: TextStyle(color: Colors.white70)));
        }
        return StreamBuilder<Duration>(
          stream: audio.player.positionStream,
          builder: (context, ps) {
            final pos = ps.data ?? Duration.zero;
            var cur = -1;
            if (ly.synced) {
              for (var i = 0; i < ly.lines.length; i++) {
                if (ly.lines[i].at <= pos + const Duration(milliseconds: 250)) cur = i;
              }
              WidgetsBinding.instance.addPostFrameCallback((_) => _follow(cur));
            }
            return ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.12, 0.88, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ListView.builder(
                controller: _sc,
                padding: EdgeInsets.symmetric(horizontal: context.u(24), vertical: context.u(80)),
                itemCount: ly.lines.length,
                itemBuilder: (context, i) {
                  final l = ly.lines[i];
                  final on = i == cur;
                  return GestureDetector(
                    key: _keys.putIfAbsent(i, () => GlobalKey()),
                    onTap: ly.synced ? () => audio.seek(l.at) : null,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: context.u(7)),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          fontSize: on ? 26 : 22,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: !ly.synced
                              ? Colors.white.withValues(alpha: 0.85)
                              : on
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: i < cur ? 0.35 : 0.5),
                        ),
                        child: Text(l.text.isEmpty ? '♪' : l.text),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

void _showQueue(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, sc) => ValueListenableBuilder<List<Track>>(
        valueListenable: audio.tracks,
        builder: (ctx, list, _) => ValueListenableBuilder<int>(
          valueListenable: audio.index,
          builder: (ctx, cur, _) => ListView.builder(
            controller: sc,
            itemCount: list.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Очередь', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                );
              }
              final j = i - 1;
              return Dismissible(
                key: ValueKey('${list[j].id}$j'),
                direction: j == cur ? DismissDirection.none : DismissDirection.endToStart,
                onDismissed: (_) => audio.removeAt(j),
                background: Container(
                    color: Colors.redAccent,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline)),
                child: TrackTile(track: list[j], onTap: () => audio.jumpTo(j)),
              );
            },
          ),
        ),
      ),
    ),
  );
}

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/lyrics.dart';
import '../services/store.dart';
import '../ui.dart';
import '../skins/winamp.dart';
import '../vinyl.dart';
import 'lyrics_tools.dart';
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
    if (Store.instance.winamp) return const WinampPlayer();
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
                final coverSize =
                    (wide ? box.maxHeight * 0.62 : box.maxWidth - context.u(56)).clamp(120.0, 520.0).toDouble();
                final main = _lyrics && t != null
                    ? _LyricsView(track: t)
                    : Store.instance.vinyl
                        // винил: пластинка крутится, под ней — текущая строка текста песни
                        ? LayoutBuilder(builder: (context, b) {
                            final ticker = LyricsTicker.heightFor(context);
                            final s = math.min(coverSize, b.maxHeight - ticker - context.u(24)).clamp(100.0, 520.0);
                            return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              VinylDisc(track: t, size: s),
                              SizedBox(height: context.u(14)),
                              if (t != null)
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: context.u(24)),
                                  child: LyricsTicker(track: t),
                                ),
                            ]);
                          })
                        : Center(
                            child: Padding(
                              padding: EdgeInsets.all(context.u(12)),
                              child: Hero(
                                tag: 'cover',
                                child: Cover(track: t, size: coverSize, radius: context.u(18), big: true),
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
      // размытый фон — маленькая картинка, растянутая со сглаживанием (без фильтра размытия: он пересчитывался
      // каждый кадр вместе с полосой прогресса)
      Image(
        image: ResizeImage(Cover.debugImage?.call(track) ?? NetworkImage(track.art ?? track.thumb),
            width: 14, height: 14, policy: ResizeImagePolicy.fit),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox(),
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

  void _reload() => setState(() {
        _f = LyricsService.instance.get(widget.track);
        _active = -1;
        _keys.clear();
      });

  Future<void> _search() async {
    final ly = await pickLyrics(context, widget.track);
    if (ly != null) _reload();
  }

  Future<void> _own() async {
    final ly = await ownLyrics(context, widget.track);
    if (ly != null) _reload();
  }

  Future<void> _sync(Lyrics ly) async {
    final how = await showGlassSheet<String>(
      context,
      (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.touch_app_rounded),
            title: const Text('Вручную — нажимать на каждую строку'),
            subtitle: const Text('Точно: песня играет с начала, вы отмечаете строки'),
            onTap: () => Navigator.pop(ctx, 'tap'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_fix_high_rounded),
            title: const Text('Автоматически (примерно)'),
            subtitle: const Text('По длине строк; потом можно подправить сдвигом'),
            onTap: () => Navigator.pop(ctx, 'auto'),
          ),
          if (ly.source != 'lrclib' && ly.source != 'lyrics.ovh')
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('Сбросить — искать заново'),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
        ]),
      ),
    );
    if (how == null || !mounted) return;
    final texts = [for (final l in ly.lines) l.text];
    if (how == 'auto') {
      final total = audio.player.duration ?? widget.track.duration;
      await LyricsService.instance.save(widget.track, LyricsService.autoSync(texts, total));
    } else if (how == 'reset') {
      await LyricsService.instance.reset(widget.track);
    } else {
      await Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(builder: (_) => LyricsSyncScreen(track: widget.track, lines: texts)));
    }
    if (mounted) _reload();
  }

  Future<void> _shift(Lyrics ly, int ms) async {
    await LyricsService.instance.save(widget.track, ly.shifted(Duration(milliseconds: ms)));
    _reload();
  }

  /// Панель над текстом: найти другой, синхронизировать, сдвиг (раньше/позже), свой текст.
  Widget _toolbar(BuildContext context, Lyrics ly) {
    final dim = Colors.white.withValues(alpha: 0.6);
    Widget btn(IconData i, String tip, VoidCallback on) => IconButton(
        tooltip: tip, visualDensity: VisualDensity.compact, icon: Icon(i, color: Colors.white), onPressed: on);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.u(12)),
      child: Row(children: [
        Expanded(
          child: Text(
            ly.approx ? 'тайминги примерные — подправьте' : (ly.synced ? ly.source : '${ly.source} · без таймингов'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ly.approx ? context.accent : dim, fontSize: 12),
          ),
        ),
        if (ly.synced) ...[
          btn(Icons.fast_rewind_rounded, 'Текст раньше на 0,5 с', () => _shift(ly, -500)),
          btn(Icons.fast_forward_rounded, 'Текст позже на 0,5 с', () => _shift(ly, 500)),
        ],
        btn(Icons.sync_rounded, 'Синхронизировать', () => _sync(ly)),
        btn(Icons.search_rounded, 'Найти другой текст', _search),
        btn(Icons.edit_note_rounded, 'Свой текст', _own),
      ]),
    );
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
          return Center(
            child: Padding(
              padding: EdgeInsets.all(context.u(24)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Текст не найден автоматически', style: TextStyle(color: Colors.white70)),
                SizedBox(height: context.u(14)),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  FilledButton.icon(
                    onPressed: () => _search(),
                    icon: const Icon(Icons.search_rounded, color: Colors.black),
                    label: const Text('Найти вручную', style: TextStyle(color: Colors.black)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _own(),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Свой текст'),
                  ),
                ]),
              ]),
            ),
          );
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
            return Column(children: [
              _toolbar(context, ly),
              Expanded(
                  child: ShaderMask(
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
                      ))),
            ]);
          },
        );
      },
    );
  }
}

/// Очередь (как в Spotify): сильно размытое стекло поверх плеера — ничего не просвечивает;
/// «Сейчас играет», «Далее в очереди» (добавленные вручную), «Далее»; перетаскивание за ручку, ✕ — убрать.
void _showQueue(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.4,
      maxChildSize: 0.96,
      builder: (ctx, sc) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: ColoredBox(
            color: const Color(0xFF111114).withValues(alpha: 0.82),
            child: _QueueList(controller: sc),
          ),
        ),
      ),
    ),
  );
}

class _QueueList extends StatelessWidget {
  final ScrollController controller;
  const _QueueList({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([audio.tracks, audio.index, audio.upNext, audio.shuffle]),
      builder: (context, _) {
        final list = audio.tracks.value;
        final cur = audio.index.value;
        final up = audio.upNext.value.clamp(0, (list.length - cur - 1).clamp(0, list.length));
        // показываем текущий и всё, что после него (не больше 300 — длинные плейлисты)
        final first = cur + 1;
        final count = (list.length - first).clamp(0, 300);
        final dim = Colors.white.withValues(alpha: 0.55);
        Widget label(String s) => Padding(
              padding: EdgeInsets.fromLTRB(context.u(18), context.u(16), context.u(18), context.u(6)),
              child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            );
        return CustomScrollView(controller: controller, slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: Container(
                margin: EdgeInsets.only(top: context.u(10)),
                width: 40,
                height: 5,
                decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
          if (cur >= 0 && cur < list.length) ...[
            SliverToBoxAdapter(child: label('Сейчас играет')),
            SliverToBoxAdapter(child: _QueueRow(track: list[cur], playing: true)),
          ],
          if (count == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(context.u(24)),
                child: Text('Дальше ничего нет — добавьте треки свайпом вправо', style: TextStyle(color: dim)),
              ),
            ),
          if (count > 0)
            SliverReorderableList(
              itemCount: count,
              onReorderItem: (a, b) {
                // перенос внутри/в «Далее в очереди» — пересчитать, сколько там треков
                final inUpA = a < up, inUpB = b < up || (b == up && !inUpA);
                audio.move(first + a, first + b);
                if (!inUpA && inUpB) audio.upNext.value = up + 1;
                if (inUpA && !inUpB) audio.upNext.value = up - 1;
              },
              itemBuilder: (context, i) {
                final j = first + i;
                return Column(
                  key: ValueKey('q${list[j].id}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (i == 0 && up > 0) label('Далее в очереди'),
                    if (i == up) label(audio.shuffle.value ? 'Далее (вперемешку)' : 'Далее'),
                    _QueueRow(
                      track: list[j],
                      queued: i < up,
                      onTap: () => audio.jumpTo(j),
                      onRemove: () => audio.removeAt(j),
                      handle: ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: EdgeInsets.all(context.u(10)),
                          child: Icon(Icons.drag_handle_rounded, color: dim),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          SliverToBoxAdapter(child: SizedBox(height: context.u(40) + MediaQuery.paddingOf(context).bottom)),
        ]);
      },
    );
  }
}

class _QueueRow extends StatelessWidget {
  final Track track;
  final bool playing;
  final bool queued;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final Widget? handle;
  const _QueueRow(
      {required this.track, this.playing = false, this.queued = false, this.onTap, this.onRemove, this.handle});

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.55);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(context.u(16), context.u(5), context.u(4), context.u(5)),
        child: Row(children: [
          Cover(track: track, size: context.u(46), radius: context.u(8)),
          SizedBox(width: context.u(12)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: playing ? context.accent : Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              Text(track.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim, fontSize: 13)),
            ]),
          ),
          if (queued) Icon(Icons.playlist_add_check_rounded, size: context.u(18), color: context.accent),
          if (onRemove != null)
            IconButton(
              tooltip: 'Убрать из очереди',
              icon: Icon(Icons.close_rounded, color: dim, size: context.u(20)),
              onPressed: onRemove,
            ),
          if (handle != null) handle!,
          if (playing)
            Padding(
                padding: EdgeInsets.all(context.u(12)), child: Icon(Icons.graphic_eq_rounded, color: context.accent)),
        ]),
      ),
    );
  }
}

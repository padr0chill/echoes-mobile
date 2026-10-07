import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'models.dart';
import 'screens/artist_screen.dart';
import 'services/audio.dart';
import 'services/offline.dart';
import 'services/square_cover.dart';
import 'services/store.dart';
import 'skins/winamp.dart';
import 'ui.dart';
import 'i18n.dart';

/// Обложка: миниатюра YouTube, обрезанная в квадрат (без чёрных полос 16:9). Только кэш в памяти.
class Cover extends StatelessWidget {
  /// Только для тестов/скриншотов: подменить картинку обложки (в тестах нет сети).
  static ImageProvider Function(Track t)? debugImage;

  final Track? track;
  final double size;
  final double radius;
  final bool big;

  const Cover({super.key, required this.track, required this.size, this.radius = 8, this.big = false});

  @override
  Widget build(BuildContext context) {
    final t = track;
    final radius = context.echoamp ? 0.0 : this.radius; // Эховамп — квадратные обложки
    Widget ph() => Container(
          color: Theme.of(context).cardColor,
          alignment: Alignment.center,
          child: Icon(Icons.music_note_rounded, size: size * 0.4, color: context.accent.withValues(alpha: 0.7)),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: t == null
            ? ph()
            // большая обложка видео YouTube — чистый квадрат в хорошем качестве (без чёрных полос)
            : big && SquareCover.instance.needed(t) && debugImage == null
                ? _SquareYt(track: t, size: size, fallback: ph)
                : (t.art != null || !t.isYt) && debugImage == null
                    ? Image.network(t.cover,
                        fit: BoxFit.cover,
                        cacheWidth: (size * 3).round(),
                        errorBuilder: (_, __, ___) =>
                            ph()) // квадратная обложка (SoundCloud, YouTube Music) — без подрезки
                    : FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          // 4:3-миниатюра с полосами — увеличиваем, чтобы полосы ушли за край
                          width: size * 16 / 9,
                          height: size * 16 / 9 * 0.75,
                          child: debugImage != null
                              ? Image(image: debugImage!(t), fit: BoxFit.cover)
                              : Image.network(
                                  big ? t.cover : t.thumb,
                                  fit: BoxFit.cover,
                                  cacheWidth: (size * 3).round(),
                                  errorBuilder: (_, __, ___) => big
                                      ? Image.network(t.thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph())
                                      : ph(),
                                ),
                        ),
                      ),
      ),
    );
  }
}

/// Заголовок экрана: крупный текст; в Эховампе — полосатая шапка окна, как у Winamp.
class ScreenTitle extends StatelessWidget {
  final String text;
  const ScreenTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    if (context.echoamp) return WaBevel(child: WaTitleBar(title: text.toUpperCase()));
    return Text(text, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900));
  }
}

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final Playlist? playlist;
  final bool showArtist;

  const TrackTile({super.key, required this.track, required this.onTap, this.playlist, this.showArtist = true});

  @override
  Widget build(BuildContext context) {
    final cur = audio.current == track;
    final sub = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final dur = track.seconds > 0 ? fmtDuration(track.duration) : '';
    // свайп вправо — в очередь, влево — в плейлист (как в Spotify)
    return SwipeActions(
        onRight: () {
          audio.addToQueue(track);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(tr('«{0}» — в очереди', [track.title])),
              duration: const Duration(seconds: 2),
            ));
        },
        onLeft: () => pickPlaylist(context, track),
        // подсветка нажатия — скруглённая и с отступом от краёв экрана (в Эховампе — прямая)
        child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.u(6)),
            child: InkWell(
              borderRadius: BorderRadius.circular(context.r(16)),
              onTap: onTap,
              onLongPress: () => showTrackMenu(context, track, playlist: playlist),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(10), vertical: context.u(7)),
                child: Row(children: [
                  Cover(track: track, size: context.u(50), radius: context.u(8)),
                  SizedBox(width: context.u(12)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cur ? context.accent : null)),
                      const SizedBox(height: 2),
                      Row(children: [
                        // имя исполнителя — ссылка на его страницу
                        if (showArtist && track.artist.isNotEmpty)
                          Flexible(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => openArtist(context, track),
                              child: Text(track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: sub)),
                            ),
                          ),
                        if (showArtist && track.artist.isNotEmpty && dur.isNotEmpty)
                          Text('  ·  ', style: TextStyle(fontSize: 13, color: sub)),
                        if (dur.isNotEmpty) Text(dur, style: TextStyle(fontSize: 13, color: sub)),
                        OfflineMark(track: track),
                      ]),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () => showTrackMenu(context, track, playlist: playlist),
                  ),
                ]),
              ),
            )));
  }
}

/// Свайп по строке, как в Spotify: вправо — зелёная полоса «В очередь», влево — «В плейлист».
/// Строка тянется за пальцем, после порога — лёгкая вибрация, отпустили — действие и пружинкой назад.
class SwipeActions extends StatefulWidget {
  final Widget child;
  final VoidCallback onRight;
  final VoidCallback onLeft;
  const SwipeActions({super.key, required this.child, required this.onRight, required this.onLeft});

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  double _dx = 0, _raw = 0, _from = 0, _w = 360;
  bool _armed = false;

  double get _threshold => (_w * 0.26).clamp(72.0, 140.0);

  @override
  void initState() {
    super.initState();
    _back.addListener(() => setState(() => _dx = _from * (1 - Curves.easeOutBack.transform(_back.value))));
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    if (_back.isAnimating) {
      _back.stop();
      _raw = _dx;
    }
    // палец — _raw; строка идёт за ним 1:1 до порога, дальше — туже (только сверх порога)
    _raw = (_raw + d.delta.dx).clamp(-_w, _w);
    final over = _raw.abs() - _threshold;
    final dx = over <= 0 ? _raw : _raw.sign * (_threshold + over * 0.45);
    final armed = dx.abs() >= _threshold;
    if (armed != _armed) {
      _armed = armed;
      HapticFeedback.mediumImpact();
    }
    setState(() => _dx = dx);
  }

  void _end(DragEndDetails d) {
    if (_dx >= _threshold) widget.onRight();
    if (_dx <= -_threshold) widget.onLeft();
    _armed = false;
    _raw = 0;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _w = box.maxWidth;
      final right = _dx > 0;
      final p = (_dx.abs() / _threshold).clamp(0.0, 1.0);
      final color = right ? const Color(0xFF1DB954) : context.accent;
      return GestureDetector(
        onHorizontalDragUpdate: _update,
        onHorizontalDragEnd: _end,
        onHorizontalDragCancel: () => _end(DragEndDetails()),
        child: Stack(children: [
          if (_dx != 0)
            Positioned.fill(
              child: Container(
                color: color.withValues(alpha: 0.25 + 0.6 * p),
                alignment: right ? Alignment.centerLeft : Alignment.centerRight,
                padding: EdgeInsets.symmetric(horizontal: context.u(22)),
                child: Transform.scale(
                  scale: 0.7 + 0.3 * p + (_dx.abs() >= _threshold ? 0.12 : 0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!right && p > 0.6)
                      Text(tr('В плейлист'),
                          style: TextStyle(color: Colors.black.withValues(alpha: p), fontWeight: FontWeight.w800)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.u(6)),
                      child: Icon(right ? Icons.queue_music_rounded : Icons.playlist_add_rounded,
                          color: Colors.black.withValues(alpha: 0.5 + 0.5 * p)),
                    ),
                    if (right && p > 0.6)
                      Text(tr('В очередь'),
                          style: TextStyle(color: Colors.black.withValues(alpha: p), fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: ColoredBox(
              color: _dx == 0 ? Colors.transparent : Theme.of(context).scaffoldBackgroundColor,
              child: widget.child,
            ),
          ),
        ]),
      );
    });
  }
}

/// Значок у трека: скачан (галочка) или качается (кольцо прогресса).
class OfflineMark extends StatelessWidget {
  final Track track;
  const OfflineMark({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Offline.instance,
      builder: (context, _) {
        final o = Offline.instance;
        final s = context.u(14);
        Widget? w;
        if (o.has(track)) {
          w = Icon(Icons.download_done_rounded, size: s, color: context.accent);
        } else if (o.busy(track)) {
          w = SizedBox(
            width: s * 0.9,
            height: s * 0.9,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: (o.progress[track.id] ?? 0) > 0 ? o.progress[track.id] : null,
              color: context.accent,
            ),
          );
        } else if (o.failed.containsKey(track.id)) {
          w = Tooltip(
            message: o.failed[track.id]!,
            child: Icon(Icons.error_outline_rounded, size: s, color: const Color(0xFFFF8A80)),
          );
        }
        if (w == null) return const SizedBox.shrink();
        return Padding(padding: EdgeInsets.only(left: context.u(6)), child: w);
      },
    );
  }
}

Future<void> showTrackMenu(BuildContext context, Track t, {Playlist? playlist}) {
  final st = Store.instance;
  return showGlassSheet(
    context,
    (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Cover(track: t, size: 44),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Divider(height: 1),
        if (t.artist.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.person_rounded),
            title: Text(tr('Перейти к исполнителю: {0}', [t.artist]), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(ctx);
              openArtist(context, t);
            },
          ),
        ListTile(
          leading: Icon(st.isLiked(t) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
          title: Text(st.isLiked(t) ? tr('Убрать из «Мне нравится»') : tr('Мне нравится')),
          onTap: () {
            st.toggleLike(t);
            Navigator.pop(ctx);
          },
        ),
        if (Offline.instance.has(t))
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: Text(tr('Удалить из загрузок')),
            onTap: () {
              Offline.instance.remove(t);
              Navigator.pop(ctx);
            },
          )
        else
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: Text(Offline.instance.busy(t) ? tr('Скачивается…') : tr('Скачать в приложение')),
            subtitle: Text(tr('Будет играть без интернета')),
            onTap: () {
              Offline.instance.download(t);
              Navigator.pop(ctx);
            },
          ),
        ListTile(
          leading: const Icon(Icons.playlist_play_rounded),
          title: Text(tr('Играть следующим')),
          onTap: () {
            audio.playNext(t);
            Navigator.pop(ctx);
          },
        ),
        ListTile(
          leading: const Icon(Icons.queue_music_rounded),
          title: Text(tr('В конец очереди')),
          onTap: () {
            audio.addToQueue(t);
            Navigator.pop(ctx);
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add_rounded),
          title: Text(tr('Добавить в плейлист')),
          onTap: () {
            Navigator.pop(ctx);
            pickPlaylist(context, t);
          },
        ),
        if (playlist != null)
          ListTile(
            leading: const Icon(Icons.remove_circle_outline_rounded),
            title: Text(tr('Убрать из «{0}»', [playlist.name])),
            onTap: () {
              st.removeFromPlaylist(playlist, t);
              Navigator.pop(ctx);
            },
          ),
      ]),
    ),
  );
}

Future<void> pickPlaylist(BuildContext context, Track t) async {
  final st = Store.instance;
  await showGlassSheet(
    context,
    (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: Text(tr('Новый плейлист')),
          onTap: () async {
            Navigator.pop(ctx);
            final name = await askText(context, tr('Новый плейлист'), tr('Название'));
            if (name != null) st.addToPlaylist(st.createPlaylist(name), t);
          },
        ),
        for (final p in st.playlists)
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: Text(p.name),
            subtitle: Text(tr('{0} тр.', [p.tracks.length])),
            onTap: () {
              st.addToPlaylist(p, t);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Добавлено в «{0}»', [p.name]))));
            },
          ),
      ]),
    ),
  );
}

Future<String?> askText(BuildContext context, String title, String hint, {String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Отмена'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Готово'))),
      ],
    ),
  );
}

/// Мини-плеер над нижней панелью: обложка, название, прогресс, play/pause, следующий.
class MiniPlayer extends StatelessWidget {
  final VoidCallback onOpen;
  const MiniPlayer({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: audio.trackKey,
      builder: (context, _, __) {
        final t = audio.current;
        if (t == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: onOpen,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -200) onOpen();
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(context.u(10), 0, context.u(10), context.u(8)),
            // мини-плеер — стеклянная капсула, как в iOS
            child: Glass(
              radius: context.u(22),
              tint: 1.3,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: EdgeInsets.all(context.u(8)),
                  child: Row(children: [
                    Hero(tag: 'cover', child: Cover(track: t, size: context.u(44), radius: context.u(8))),
                    SizedBox(width: context.u(10)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
                      ]),
                    ),
                    const PlayPauseButton(size: 40),
                    IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: audio.skipToNext),
                  ]),
                ),
                const _ThinProgress(),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _ThinProgress extends StatelessWidget {
  const _ThinProgress();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audio.player.positionStream,
      builder: (context, snap) {
        final d = audio.player.duration ?? Duration.zero;
        final p = snap.data ?? Duration.zero;
        final f = d.inMilliseconds > 0 ? (p.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0) : 0.0;
        return LinearProgressIndicator(
          value: f,
          minHeight: 2,
          backgroundColor: Colors.transparent,
          color: context.accent,
        );
      },
    );
  }
}

class PlayPauseButton extends StatelessWidget {
  final double size;
  final bool filled;
  const PlayPauseButton({super.key, this.size = 40, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: audio.loading,
      builder: (context, loading, _) => StreamBuilder<bool>(
        stream: audio.player.playingStream,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          final s = context.u(size);
          final icon = loading
              ? SizedBox(
                  width: s * 0.45,
                  height: s * 0.45,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: filled ? Colors.black : context.accent))
              : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: s * (filled ? 0.55 : 0.7), color: filled ? Colors.black : null);
          return SizedBox(
            width: s,
            height: s,
            child: Material(
              color: filled ? context.accent : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => playing ? audio.pause() : audio.play(),
                child: Center(child: icon),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Шапка раздела крупным шрифтом, как в ECHOES.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.u(16), context.u(18), context.u(8), context.u(6)),
      child: Row(children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Квадратная обложка видео YouTube без полос: готовая — сразу, иначе — пока делается, обычное превью.
class _SquareYt extends StatelessWidget {
  final Track track;
  final double size;
  final Widget Function() fallback;
  const _SquareYt({required this.track, required this.size, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final ready = SquareCover.instance.ready(track);
    Widget file(File f) =>
        Image.file(f, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => fallback());
    if (ready != null) return file(ready);
    return FutureBuilder<File?>(
      future: SquareCover.instance.get(track),
      builder: (context, s) => s.data != null
          ? file(s.data!)
          : Image.network(track.thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback()),
    );
  }
}

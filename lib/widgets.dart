import 'package:flutter/material.dart';

import 'models.dart';
import 'services/audio.dart';
import 'services/store.dart';
import 'ui.dart';

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
            : t.isSc && debugImage == null
                ? Image.network(t.cover, fit: BoxFit.cover, cacheWidth: (size * 3).round(),
                    errorBuilder: (_, __, ___) => ph()) // квадратная обложка SoundCloud — без подрезки
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

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final Playlist? playlist;

  const TrackTile({super.key, required this.track, required this.onTap, this.playlist});

  @override
  Widget build(BuildContext context) {
    final cur = audio.current == track;
    final sub = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return InkWell(
      onTap: onTap,
      onLongPress: () => showTrackMenu(context, track, playlist: playlist),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(7)),
        child: Row(children: [
          Cover(track: track, size: context.u(50), radius: context.u(8)),
          SizedBox(width: context.u(12)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cur ? context.accent : null)),
              const SizedBox(height: 2),
              Text(
                  [track.artist, if (track.seconds > 0) fmtDuration(track.duration)].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: sub)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () => showTrackMenu(context, track, playlist: playlist),
          ),
        ]),
      ),
    );
  }
}

Future<void> showTrackMenu(BuildContext context, Track t, {Playlist? playlist}) {
  final st = Store.instance;
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Cover(track: t, size: 44),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(st.isLiked(t) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
          title: Text(st.isLiked(t) ? 'Убрать из «Мне нравится»' : 'Мне нравится'),
          onTap: () {
            st.toggleLike(t);
            Navigator.pop(ctx);
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_play_rounded),
          title: const Text('Играть следующим'),
          onTap: () {
            audio.playNext(t);
            Navigator.pop(ctx);
          },
        ),
        ListTile(
          leading: const Icon(Icons.queue_music_rounded),
          title: const Text('В конец очереди'),
          onTap: () {
            audio.addToQueue(t);
            Navigator.pop(ctx);
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add_rounded),
          title: const Text('Добавить в плейлист'),
          onTap: () {
            Navigator.pop(ctx);
            pickPlaylist(context, t);
          },
        ),
        if (playlist != null)
          ListTile(
            leading: const Icon(Icons.remove_circle_outline_rounded),
            title: Text('Убрать из «${playlist.name}»'),
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
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: const Text('Новый плейлист'),
          onTap: () async {
            Navigator.pop(ctx);
            final name = await askText(context, 'Новый плейлист', 'Название');
            if (name != null) st.addToPlaylist(st.createPlaylist(name), t);
          },
        ),
        for (final p in st.playlists)
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: Text(p.name),
            subtitle: Text('${p.tracks.length} тр.'),
            onTap: () {
              st.addToPlaylist(p, t);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добавлено в «${p.name}»')));
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
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Готово')),
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
      valueListenable: audio.index,
      builder: (context, _, __) {
        final t = audio.current;
        if (t == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: onOpen,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -200) onOpen();
          },
          child: Container(
            margin: EdgeInsets.fromLTRB(context.u(8), 0, context.u(8), context.u(6)),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(context.u(14)),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 4))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: EdgeInsets.all(context.u(8)),
                child: Row(children: [
                  Hero(tag: 'cover', child: Cover(track: t, size: context.u(44), radius: context.u(8))),
                  SizedBox(width: context.u(10)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
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

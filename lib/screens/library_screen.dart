import 'package:flutter/material.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/store.dart';
import '../ui.dart';
import '../widgets.dart';
import 'import_flow.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = Store.instance;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(bottom: context.u(200)),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(16), 0),
              child: const Text('Моя музыка', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            ),
            _Card(
              icon: Icons.favorite_rounded,
              title: 'Мне нравится',
              sub: '${st.liked.length} тр.',
              onTap: () => _open(context, 'Мне нравится', () => st.liked),
            ),
            _Card(
              icon: Icons.computer_rounded,
              title: 'Импорт с ПК',
              sub: 'Плейлисты из ECHOES на компьютере',
              onTap: () => importFromPc(context),
            ),
            SectionTitle('Плейлисты',
                trailing: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () async {
                    final n = await askText(context, 'Новый плейлист', 'Название');
                    if (n != null) st.createPlaylist(n);
                  },
                )),
            if (st.playlists.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                child: const Text('Плейлистов пока нет — нажмите «+» или «Добавить в плейлист» у трека'),
              ),
            for (final p in st.playlists)
              _Card(
                icon: Icons.queue_music_rounded,
                title: p.name,
                sub: '${p.tracks.length} тр.',
                onTap: () => _open(context, p.name, () => p.tracks, playlist: p),
              ),
            if (st.history.isNotEmpty) const SectionTitle('Недавно играли'),
            for (var i = 0; i < st.history.length && i < 30; i++)
              TrackTile(track: st.history[i], onTap: () => audio.playList(st.history, i)),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, String title, List<Track> Function() tracks, {Playlist? playlist}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackListScreen(title: title, tracks: tracks, playlist: playlist),
    ));
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _Card({required this.icon, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.u(16), context.u(8), context.u(16), 0),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(context.u(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(context.u(14)),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(context.u(12)),
            child: Row(children: [
              Container(
                width: context.u(48),
                height: context.u(48),
                decoration: BoxDecoration(
                  color: context.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(context.u(10)),
                ),
                child: Icon(icon, color: context.accent),
              ),
              SizedBox(width: context.u(12)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(sub,
                      style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }
}

class TrackListScreen extends StatelessWidget {
  final String title;
  final List<Track> Function() tracks;
  final Playlist? playlist;
  const TrackListScreen({super.key, required this.title, required this.tracks, this.playlist});

  @override
  Widget build(BuildContext context) {
    final st = Store.instance;
    return Ambient(
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(playlist?.name ?? title),
        actions: [
          if (playlist != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final n = await askText(context, 'Переименовать', 'Название', initial: playlist!.name);
                  if (n != null) st.renamePlaylist(playlist!, n);
                } else if (v == 'delete') {
                  st.deletePlaylist(playlist!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(value: 'delete', child: Text('Удалить плейлист')),
              ],
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: st,
        builder: (context, _) {
          final list = tracks();
          if (list.isEmpty) {
            return const Center(child: Text('Пока пусто'));
          }
          return ListView(
            padding: EdgeInsets.only(bottom: context.u(200)),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(8)),
                child: Row(children: [
                  FilledButton.icon(
                    onPressed: () => audio.playList(list, 0),
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                    label: const Text('Слушать', style: TextStyle(color: Colors.black)),
                  ),
                  SizedBox(width: context.u(8)),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (!audio.shuffle.value) audio.toggleShuffle();
                      audio.playList(list, DateTime.now().millisecondsSinceEpoch % list.length);
                    },
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Вперемешку'),
                  ),
                ]),
              ),
              for (var i = 0; i < list.length; i++)
                TrackTile(track: list[i], playlist: playlist, onTap: () => audio.playList(list, i)),
            ],
          );
        },
      ),
    ));
  }
}

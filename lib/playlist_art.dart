import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'glass.dart';
import 'i18n.dart';
import 'models.dart';
import 'services/store.dart';
import 'ui.dart';
import 'widgets.dart';

/// Обложка плейлиста: своя картинка, иначе — мозаика 2×2 из обложек первых треков (как в Spotify),
/// у короткого плейлиста — обложка первого трека, у пустого — значок.
class PlaylistArt extends StatelessWidget {
  final Playlist playlist;
  final double size;
  final double radius;
  const PlaylistArt({super.key, required this.playlist, required this.size, this.radius = 6});

  static File? file(Playlist p) {
    final c = p.cover;
    final dir = Store.supportDir;
    if (c == null || dir == null) return null;
    final f = File('$dir/playlist_covers/$c');
    return f.existsSync() ? f : null;
  }

  @override
  Widget build(BuildContext context) {
    final own = file(playlist);
    Widget child;
    if (own != null) {
      child = Image.file(own, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      final seen = <String>{};
      final covers = [
        for (final t in playlist.tracks)
          if (seen.add(t.art ?? t.id)) t
      ].take(4).toList();
      if (covers.length >= 4) {
        final h = size / 2;
        child = SizedBox(
          width: size,
          height: size,
          child: Column(children: [
            Row(children: [
              Cover(track: covers[0], size: h, radius: 0),
              Cover(track: covers[1], size: h, radius: 0),
            ]),
            Row(children: [
              Cover(track: covers[2], size: h, radius: 0),
              Cover(track: covers[3], size: h, radius: 0),
            ]),
          ]),
        );
      } else if (covers.isNotEmpty) {
        child = Cover(track: covers.first, size: size, radius: 0);
      } else {
        child = Container(
          width: size,
          height: size,
          color: context.accent.withValues(alpha: 0.18),
          child: Icon(Icons.queue_music_rounded, color: context.accent, size: size * 0.42),
        );
      }
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

/// Сменить обложку плейлиста: фото из галереи или «Файлов»; «Убрать» — вернуть мозаику из треков.
Future<void> pickPlaylistCover(BuildContext context, Playlist p) async {
  final choice = await showGlassSheet<String>(
    context,
    (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_library_rounded),
          title: Text(tr('Из галереи')),
          onTap: () => Navigator.pop(ctx, 'gallery'),
        ),
        ListTile(
          leading: const Icon(Icons.folder_rounded),
          title: Text(tr('Из «Файлов»')),
          onTap: () => Navigator.pop(ctx, 'files'),
        ),
        if (p.cover != null)
          ListTile(
            leading: const Icon(Icons.grid_view_rounded),
            title: Text(tr('Обложка из треков')),
            onTap: () => Navigator.pop(ctx, 'reset'),
          ),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'reset') {
    Store.instance.setPlaylistCover(p, null);
    return;
  }
  XFile? f;
  try {
    f = choice == 'gallery'
        ? await ImagePicker().pickImage(
            source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 88, requestFullMetadata: false)
        : await openFile(acceptedTypeGroups: [
            XTypeGroup(
                label: tr('Фото'),
                extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
                uniformTypeIdentifiers: ['public.image']),
          ]);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Не удалось открыть фото: {0}', [e]))));
    }
    return;
  }
  if (f == null) return;
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/playlist_covers');
  await dir.create(recursive: true);
  final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'jpg';
  final name = 'pl_${DateTime.now().millisecondsSinceEpoch}.$ext';
  await File('${dir.path}/$name').writeAsBytes(await f.readAsBytes());
  final old = PlaylistArt.file(p);
  Store.instance.setPlaylistCover(p, name);
  try {
    await old?.delete();
  } catch (_) {}
}

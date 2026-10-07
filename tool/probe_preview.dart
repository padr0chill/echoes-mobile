// ignore_for_file: avoid_print
import 'package:echoes_mobile/services/sc.dart';
import 'package:echoes_mobile/services/yt.dart';

/// Отрывки Go+ с SoundCloud → какое видео YouTube для них находится.
Future<void> main() async {
  final al = await ScService.instance.searchAlbums('hybrid theory');
  final tracks = await ScService.instance.albumTracks(al.first.id);
  for (final t in tracks.take(8)) {
    final id = await YtService.instance.findSame(t);
    print('${t.isPreview ? 'отрывок' : 'полный'} ${t.artist} — ${t.title} (${t.seconds}s) → https://youtu.be/$id');
  }
}

// ignore_for_file: avoid_print
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  const id = '8P0vKLHbtMg';
  final variants = <String, List<YoutubeApiClient>?>{
    'default': null,
    'ios': [YoutubeApiClient.ios],
    'androidVr': [YoutubeApiClient.androidVr],
    'ios+androidVr': [YoutubeApiClient.ios, YoutubeApiClient.androidVr],
  };
  for (final e in variants.entries) {
    final sw = Stopwatch()..start();
    try {
      final m = e.value == null
          ? await yt.videos.streamsClient.getManifest(id)
          : await yt.videos.streamsClient.getManifest(id, ytClients: e.value);
      final a = m.audioOnly.where((s) => s.container == StreamContainer.mp4).toList();
      print('${e.key}: ${sw.elapsedMilliseconds} ms, mp4 audio: ${a.map((s) => s.tag).toList()}');
    } catch (err) {
      print('${e.key}: FAIL ${sw.elapsedMilliseconds} ms $err');
    }
  }
  yt.close();
}

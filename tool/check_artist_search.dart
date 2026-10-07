// ignore_for_file: avoid_print
import 'package:echoes_mobile/services/sc.dart';
import 'package:echoes_mobile/services/text_match.dart';
Future<void> main() async {
  for (final q in ['zxcursed', 'кишлак', 'linkin park', 'torontokyo']) {
    final r = await ScService.instance.searchArtists(q);
    final rel = r.where((a) => TextMatch.similarity(q, a.name) >= 0.5 || TextMatch.similarity(a.name, q) >= 0.5).toList()
      ..sort((a, b) => b.followers.compareTo(a.followers));
    print('«$q»: ${rel.take(4).map((a) => '${a.name}${a.verified ? ' ✓' : ''} (${a.followers})').join(', ')}');
  }
}

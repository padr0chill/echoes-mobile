// ignore_for_file: avoid_print
// Данные исполнителя на SoundCloud: поиск, профиль, популярные и все треки.
import 'dart:convert';

import 'package:echoes_mobile/services/sc.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final cid = await ScService.instance.clientId();
  Future<dynamic> get(String path, [Map<String, String> q = const {}]) async {
    final r = await http.get(Uri.https('api-v2.soundcloud.com', path, {...q, 'client_id': cid}));
    print('$path -> ${r.statusCode}');
    return r.statusCode == 200 ? jsonDecode(r.body) : null;
  }

  final name = args.isNotEmpty ? args.join(' ') : 'Linkin Park';
  final users = await get('/search/users', {'q': name, 'limit': '5'});
  for (final u in (users['collection'] as List)) {
    print('  ${u['username']} id=${u['id']} followers=${u['followers_count']} tracks=${u['track_count']} '
        'verified=${u['verified']} avatar=${(u['avatar_url'] ?? '').toString().isNotEmpty} banner=${u['visuals'] != null}');
  }
  final id = (users['collection'] as List).first['id'];
  final top = await get('/users/$id/toptracks', {'limit': '10'});
  print('  toptracks: ${(top?['collection'] as List?)?.length}');
  final all = await get('/users/$id/tracks', {'limit': '50'});
  print('  tracks: ${(all?['collection'] as List?)?.length}');
  final u = await get('/users/$id');
  print('  profile: ${u?['username']} city=${u?['city']} desc=${(u?['description'] ?? '').toString().length} chars');
}

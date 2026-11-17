import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models.dart';
import 'net_protocol.dart';
import 'net_relays.dart';

class NetNote {
  NetNote(this.event)
    : id = event['id'] as String,
      author = event['pubkey'] as String,
      text = netText(event['content'], 4000),
      date = DateTime.fromMillisecondsSinceEpoch(
        (event['created_at'] as int) * 1000,
      ),
      track = _track(netObject(netDecode(netTag(event, 'echoes'))['track']));

  final NetJson event;
  final String id, author, text;
  final DateTime date;
  final Track? track;
  String get shortAuthor => '${author.substring(0, 8)}…';
}

class NetPlaylist {
  NetPlaylist(this.name, this.description, this.tracks);
  final String name, description;
  final List<Track> tracks;
}

class NetProfile {
  NetProfile({
    required this.name,
    required this.about,
    required this.status,
    required this.playlists,
  });
  final String name, about, status;
  final List<NetPlaylist> playlists;
}

class EchoesNet {
  const EchoesNet({
    this.relays = const NetRelays(),
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
  });

  final NetRelays relays;
  final FlutterSecureStorage storage;
  static const _storageKey = 'net.identity.v1';

  Future<NetIdentity?> loadIdentity() async {
    final key = await storage.read(key: _storageKey);
    return key == null
        ? null
        : NetIdentity.fromSeed(NetIdentity.parseSeed(key));
  }

  Future<NetIdentity> signIn(String key) async {
    final seed = NetIdentity.parseSeed(key);
    final identity = await NetIdentity.fromSeed(seed);
    await storage.write(key: _storageKey, value: base64Encode(seed));
    return identity;
  }

  Future<void> signOut() => storage.delete(key: _storageKey);

  Future<List<NetNote>> feed({String? me}) async {
    final events = await relays.read({
      'kinds': [1],
      '#t': ['echoes'],
      'limit': 160,
    });
    return [
      for (final e in events)
        if (netTag(e, 'e').isEmpty &&
            netText(e['content'], 4001).runes.length <= 4000 &&
            (e['pubkey'] == me || netWork(e['id'] as String) >= 10))
          NetNote(e),
    ].take(100).toList();
  }

  Future<({List<NetNote> replies, Set<String> likes})> thread(
    NetNote note,
  ) async {
    final events = await relays.read({
      'kinds': [1, 7],
      '#t': ['echoes'],
      '#e': [note.id],
      'limit': 160,
    });
    return (
      replies: [
        for (final e in events.reversed)
          if (e['kind'] == 1 &&
              netTag(e, 'e') == note.id &&
              netWork(e['id'] as String) >= 8)
            NetNote(e),
      ],
      likes: {
        for (final e in events)
          if (e['kind'] == 7) e['pubkey'] as String,
      },
    );
  }

  Future<Map<String, String>> authorNames(Iterable<String> authors) async {
    final keys = authors.toSet().take(64).toList();
    if (keys.isEmpty) return {};
    final events = await relays.read({
      'kinds': [0],
      'authors': keys,
      'limit': keys.length,
    }, budget: keys.length * 2);
    final names = <String, String>{};
    for (final event in events) {
      final data = netDecode(event['content'] as String);
      names.putIfAbsent(
        event['pubkey'] as String,
        () => netText(data['name'] ?? data['display_name'], 40),
      );
    }
    return names;
  }

  Future<NetProfile?> profile(String pubkey, {String? onion}) async {
    final results = await Future.wait(
      [
        relays.read({
          'kinds': [0],
          'authors': [pubkey],
          'limit': 10,
        }, budget: 20),
        relays.read({
          'kinds': [30078],
          'authors': [pubkey],
          '#d': ['echoes-profile', 'echoes-playlists'],
          'limit': 20,
        }, budget: 35),
      ].map(
        (future) => future.then<List<NetJson>?>(
          (value) => value,
          onError: (Object _) => null,
        ),
      ),
    );
    if (results.every((result) => result == null)) throw const NetUnavailable();

    final basic = results.first?.firstOrNull;
    final full = <String, NetJson>{};
    for (final event in results.last ?? const <NetJson>[]) {
      final d = netTag(event, 'd');
      if (full.containsKey(d)) continue;
      final link = await netLinkedOnion(event);
      if (link.isNotEmpty && (onion == null || onion == link)) {
        full[d] = netDecode(event['content'] as String);
      }
    }
    if (basic == null && full.isEmpty) return null;

    final data = full['echoes-profile'] ?? const {};
    final metadata = basic == null
        ? const <String, dynamic>{}
        : netDecode(basic['content'] as String);
    final echo = netObject(metadata['echoes']);
    return NetProfile(
      name: netText(
        data['name'] ?? metadata['name'] ?? metadata['display_name'],
        40,
      ),
      about: netText(data['about'] ?? metadata['about'], 1000),
      status: netText(data['status'] ?? echo['status'], 120),
      playlists: _playlists(full['echoes-playlists']?['pls'] ?? data['pls']),
    );
  }

  Future<void> post(NetIdentity account, String text, Track? track) async {
    final attachment = track == null
        ? ''
        : '\n\nТрек: ${netText(track.artist, 200)} — ${netText(track.title, 300)}';
    final content = netText(text, 4000 - attachment.runes.length) + attachment;
    final trackData = track == null
        ? null
        : {
            'title': netText(track.title, 300),
            'artist': netText(track.artist, 200),
            'album': '',
            'duration': track.seconds,
            if (track.isYt && _videoId.hasMatch(track.id))
              'url': 'https://www.youtube.com/watch?v=${track.id}',
          };
    await _send(account, 1, content.trim(), [
      ['t', 'echoes'],
      ['client', 'ECHOES'],
      [
        'echoes',
        jsonEncode({'track': trackData}),
      ],
    ], work: 14);
  }

  Future<void> reply(NetIdentity account, NetNote parent, String text) =>
      _send(account, 1, text, [
        ['e', parent.id, '', 'reply'],
        ['p', parent.author],
        ['t', 'echoes'],
      ], work: 8);

  Future<void> like(NetIdentity account, NetNote note) =>
      _send(account, 7, '+', [
        ['e', note.id],
        ['p', note.author],
        ['t', 'echoes'],
      ]);

  Future<void> _send(
    NetIdentity account,
    int kind,
    String text,
    List<List<String>> tags, {
    int work = 0,
  }) async {
    final event = await account.event(
      kind,
      netText(text, 4000),
      tags,
      work: work,
    );
    if (await relays.publish(event) == 0) throw const NetUnavailable();
  }
}

final _videoId = RegExp(r'^[a-zA-Z0-9_-]{11}$');

Track? _track(NetJson data) {
  final title = netText(data['title'], 300),
      artist = netText(data['artist'], 200);
  if (title.isEmpty) return null;
  final url = Uri.tryParse(netText(data['url'], 300));
  String? youtube;
  if (url != null && url.scheme == 'https') {
    if (url.host == 'youtu.be') youtube = url.pathSegments.firstOrNull;
    if (url.host == 'youtube.com' || url.host.endsWith('.youtube.com')) {
      youtube = url.queryParameters['v'];
    }
  }
  final id = youtube != null && _videoId.hasMatch(youtube)
      ? youtube
      : 'q:$artist — $title';
  final duration = data['duration'];
  return Track(
    id: id,
    title: title,
    artist: artist,
    seconds: duration is num && duration.isFinite
        ? duration.toInt().clamp(0, 36000)
        : 0,
  );
}

List<NetPlaylist> _playlists(Object? raw) {
  if (raw is! List) return [];
  final playlists = <NetPlaylist>[];
  for (final item in raw.take(6)) {
    final pl = netObject(item);
    final name = netText(pl['name'], 100);
    final tracks = pl['tracks'];
    if (name.isEmpty || tracks is! List) continue;
    final parsed = tracks
        .take(60)
        .map((item) => _track(netObject(item)))
        .nonNulls
        .toList();
    if (parsed.isNotEmpty) {
      playlists.add(NetPlaylist(name, netText(pl['desc'], 300), parsed));
    }
  }
  return playlists;
}

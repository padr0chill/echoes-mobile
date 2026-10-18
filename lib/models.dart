/// Трек — только сведения и ссылка на источник (YouTube или SoundCloud); звук не хранится, а стримится.
/// id: «xxxxxxxxxxx» — видео YouTube, «sc:12345» — трек SoundCloud,
/// «scp:12345» — на SoundCloud только 30-секундный отрывок (Go+): звук ищем на YouTube по названию,
/// «q:Исполнитель — Название» — источник неизвестен (импорт из списка): тоже ищем по названию.
class Track {
  final String id;
  final String title;
  final String artist;
  final int seconds;
  final String? art; // обложка (SoundCloud); у YouTube — миниатюра видео
  final int? artistId; // аккаунт исполнителя на SoundCloud (для страницы исполнителя)

  const Track({required this.id, required this.title, required this.artist, this.seconds = 0, this.art, this.artistId});

  bool get isSc => id.startsWith('sc:');
  int get scId => int.parse(id.substring(id.indexOf(':') + 1));
  bool get isPreview => id.startsWith('scp:');
  bool get isQuery => id.startsWith('q:');
  bool get needsLookup => isPreview || isQuery; // звук — поиском по исполнителю и названию
  bool get isLocal => id.startsWith('local:'); // свой аудиофайл с телефона
  bool get isYt => !isSc && !needsLookup && !isLocal;

  /// Обложка: своя (art) или кадр YouTube. У треков не с YouTube (свои файлы, импорт, SoundCloud без
  /// обложки) кадра нет — null (а не ссылка, которая каждый раз отвечает 404).
  String? get thumb => art ?? (isYt ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg' : null);
  String? get cover => art ?? (isYt ? 'https://i.ytimg.com/vi/$id/maxresdefault.jpg' : null);

  Duration get duration => Duration(seconds: seconds);

  Map<String, dynamic> toJson() => {
    'id': id,
    't': title,
    'a': artist,
    's': seconds,
    if (art != null) 'art': art,
    if (artistId != null) 'aid': artistId,
  };

  factory Track.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) throw const FormatException('track without id');
    final art = j['art'], aid = j['aid'];
    return Track(
      id: id,
      title: '${j['t'] ?? ''}',
      artist: '${j['a'] ?? ''}',
      seconds: (j['s'] as num?)?.toInt() ?? 0, // бывает 215.0
      art: art is String ? art : null,
      artistId: aid is num ? aid.toInt() : null,
    );
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class Playlist {
  String name;
  final List<Track> tracks;
  String? cover; // своя обложка — имя файла в папке приложения (playlist_covers/…)
  int touched; // когда меняли/слушали (мс) — для сортировки «Недавние»

  Playlist(this.name, [List<Track>? tracks, this.cover, int? touched])
    : tracks = tracks ?? [],
      touched = touched ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'n': name,
    'tr': tracks.map((t) => t.toJson()).toList(),
    if (cover != null) 'c': cover,
    'tm': touched,
  };

  factory Playlist.fromJson(Map<String, dynamic> j) {
    final raw = j['tr'], c = j['c'];
    final tracks = <Track>[];
    for (final e in raw is List ? raw : const []) {
      try {
        tracks.add(Track.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (_) {} // один битый трек не должен терять весь плейлист
    }
    return Playlist('${j['n'] ?? 'Плейлист'}', tracks, c is String ? c : null, (j['tm'] as num?)?.toInt() ?? 0);
  }
}

/// «Исполнитель - Название» из заголовка YouTube; канал «… - Topic» → исполнитель.
Track trackFromVideo(String id, String rawTitle, String author, Duration? d) {
  var artist = author.replaceAll(RegExp(r'\s*-\s*Topic$'), '').replaceAll(RegExp(r'VEVO$'), '').trim();
  var title = rawTitle;
  title = title.replaceAll(
    RegExp(
      r'\s*[\(\[](official\s*(music\s*)?(video|audio|lyric[s]?\s*video)|lyrics?|audio|clip|hd|4k)[\)\]]',
      caseSensitive: false,
    ),
    '',
  );
  final dash = title.indexOf(' - ');
  if (dash > 0 && dash < title.length - 3) {
    artist = title.substring(0, dash).trim();
    title = title.substring(dash + 3).trim();
  }
  return Track(id: id, title: title.trim(), artist: artist, seconds: d?.inSeconds ?? 0);
}

String fmtDuration(Duration d) {
  final s = d.inSeconds;
  if (s >= 3600) {
    return '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

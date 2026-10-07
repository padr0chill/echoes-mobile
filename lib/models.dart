/// Трек — только сведения и ссылка на источник (YouTube или SoundCloud); звук не хранится, а стримится.
/// id: «xxxxxxxxxxx» — видео YouTube, «sc:12345» — трек SoundCloud.
class Track {
  final String id;
  final String title;
  final String artist;
  final int seconds;
  final String? art; // обложка (SoundCloud); у YouTube — миниатюра видео

  const Track({required this.id, required this.title, required this.artist, this.seconds = 0, this.art});

  bool get isSc => id.startsWith('sc:');
  int get scId => int.parse(id.substring(3));

  String get thumb => art ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  String get cover => art ?? 'https://i.ytimg.com/vi/$id/maxresdefault.jpg';

  Duration get duration => Duration(seconds: seconds);

  Map<String, dynamic> toJson() => {'id': id, 't': title, 'a': artist, 's': seconds, if (art != null) 'art': art};

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: (j['t'] ?? '') as String,
        artist: (j['a'] ?? '') as String,
        seconds: (j['s'] ?? 0) as int,
        art: j['art'] as String?,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class Playlist {
  String name;
  final List<Track> tracks;

  Playlist(this.name, [List<Track>? tracks]) : tracks = tracks ?? [];

  Map<String, dynamic> toJson() => {'n': name, 'tr': tracks.map((t) => t.toJson()).toList()};

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        (j['n'] ?? 'Плейлист') as String,
        ((j['tr'] ?? []) as List).map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

/// «Исполнитель - Название» из заголовка YouTube; канал «… - Topic» → исполнитель.
Track trackFromVideo(String id, String rawTitle, String author, Duration? d) {
  var artist = author.replaceAll(RegExp(r'\s*-\s*Topic$'), '').replaceAll(RegExp(r'VEVO$'), '').trim();
  var title = rawTitle;
  title = title.replaceAll(RegExp(r'\s*[\(\[](official\s*(music\s*)?(video|audio|lyric[s]?\s*video)|lyrics?|audio|clip|hd|4k)[\)\]]',
      caseSensitive: false), '');
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

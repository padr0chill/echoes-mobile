import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import 'store.dart';
import 'sc.dart';
import 'stream_source.dart';
import 'yt.dart';

enum RepeatState { off, all, one }

/// Трек → карточка для экрана блокировки / пункта управления.
extension TrackMedia on Track {
  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        artist: artist,
        duration: seconds > 0 ? duration : null,
        artUri: Uri.parse(thumb),
      );
}

/// Плеер: очередь, фон и экран блокировки (audio_service), звук — потоком (just_audio, без файлов на диске).
class EchoesAudio extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  final ValueNotifier<List<Track>> tracks = ValueNotifier([]);
  final ValueNotifier<int> index = ValueNotifier(-1);
  final ValueNotifier<bool> loading = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> shuffle = ValueNotifier(false);
  final ValueNotifier<RepeatState> repeat = ValueNotifier(RepeatState.off);

  int _token = 0;
  final _rnd = Random();

  EchoesAudio() {
    player.playbackEventStream.listen((_) => _broadcast(), onError: (Object e, StackTrace st) {
      error.value = 'Поток оборвался — попробуйте ещё раз';
      _broadcast();
    });
    player.playingStream.listen((_) => _broadcast());
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
    player.durationStream.listen((d) {
      final m = mediaItem.value;
      if (d != null && m != null && m.duration != d) mediaItem.add(m.copyWith(duration: d));
    });
  }

  Track? get current {
    final i = index.value;
    final l = tracks.value;
    return i >= 0 && i < l.length ? l[i] : null;
  }

  /// Конец очереди близко (волна): что подгрузить. Сбрасывается, когда включают обычный список.
  Future<void> Function()? nearEnd;

  /// Играть список с позиции start (поиск, плейлист, «Мне нравится»). wave — очередь «Моей волны».
  Future<void> playList(List<Track> list, int start, {Future<void> Function()? wave}) async {
    nearEnd = wave;
    tracks.value = List.of(list);
    queue.add(tracks.value.map((t) => t.toMediaItem()).toList());
    await _playIndex(start);
  }

  /// Дописать треки в конец очереди (без повторов).
  void append(List<Track> more) {
    final have = tracks.value.toSet();
    final add = more.where((t) => !have.contains(t)).toList();
    if (add.isEmpty) return;
    tracks.value = [...tracks.value, ...add];
    queue.add(tracks.value.map((x) => x.toMediaItem()).toList());
  }

  // сколько секунд реально слушали трек — для профиля
  void _countListened() {
    final s = player.position.inSeconds;
    if (s > 0 && current != null) Store.instance.addListened(current!, s);
  }

  void playNext(Track t) {
    final l = List.of(tracks.value);
    final at = index.value + 1;
    l.remove(t);
    l.insert(at.clamp(0, l.length), t);
    tracks.value = l;
    queue.add(l.map((x) => x.toMediaItem()).toList());
    if (index.value < 0) _playIndex(0);
  }

  void addToQueue(Track t) {
    if (tracks.value.contains(t)) return;
    tracks.value = [...tracks.value, t];
    queue.add(tracks.value.map((x) => x.toMediaItem()).toList());
    if (index.value < 0) _playIndex(0);
  }

  void removeAt(int i) {
    if (i == index.value || i < 0 || i >= tracks.value.length) return;
    final l = List.of(tracks.value)..removeAt(i);
    if (i < index.value) index.value -= 1;
    tracks.value = l;
    queue.add(l.map((x) => x.toMediaItem()).toList());
  }

  Future<void> _playIndex(int i) async {
    final l = tracks.value;
    if (i < 0 || i >= l.length) return;
    if (player.playing || player.processingState == ProcessingState.completed) _countListened();
    index.value = i;
    final t = l[i];
    final my = ++_token;
    mediaItem.add(t.toMediaItem());
    error.value = null;
    loading.value = true;
    _broadcast();
    try {
      await player.stop();
      final ok = await _openStream(t, () => my != _token);
      if (my != _token || !ok) return;
      player.play(); // без await: завершается только в конце трека
      Store.instance.addHistory(t);
      _prefetchNext();
      final ne = nearEnd;
      if (ne != null && tracks.value.length - index.value <= 4) ne().ignore(); // волна: подгрузить ещё
    } catch (e) {
      if (my == _token) error.value = 'Не удалось открыть трек: ${_short(e, 320)}';
    } finally {
      if (my == _token) {
        loading.value = false;
        _broadcast();
      }
    }
  }

  /// Открыть звук трека. Порядок: два быстрых способа YouTube → та же песня на SoundCloud → остальные
  /// способы YouTube. YouTube бывает отказывает телефону («unplayable» — защита от ботов по IP); если так
  /// случилось, следующие треки сразу идут через SoundCloud. Удачный путь (прокси/напрямую) запоминается.
  bool _useProxy = true; // через прокси надёжнее: googlevideo часто отказывает плееру iOS напрямую
  bool _preferSc = false;

  Future<bool> _openStream(Track t, bool Function() cancelled) async {
    final eco = Store.instance.economy;
    final errs = <String>[];

    // трек SoundCloud — звук прямо оттуда (mp3 или HLS)
    if (t.isSc) {
      final st = await ScService.instance.track(t.scId);
      final u = await ScService.instance.streamUrl(st);
      if (cancelled()) return false;
      await player.setAudioSource(AudioSource.uri(u)).timeout(const Duration(seconds: 15));
      return true;
    }

    Future<bool> yt(int i) async {
      final StreamPick pick;
      try {
        pick = await YtService.instance.streamWith(t.id, i, economy: eco);
      } catch (e) {
        errs.add('YouTube#$i: ${_short(e)}');
        return false;
      }
      if (cancelled()) return false;
      for (final proxy in [_useProxy, !_useProxy]) {
        try {
          final src = proxy ? YtProxySource(pick) : AudioSource.uri(pick.url);
          await player.setAudioSource(src).timeout(const Duration(seconds: 15));
          _useProxy = proxy;
          return true;
        } catch (e) {
          errs.add('YouTube#$i${proxy ? ' прокси' : ''}: ${_short(e)}');
          if (cancelled()) return false;
        }
      }
      return false;
    }

    Future<bool> sc() async {
      try {
        final u = await ScService.instance.findSame(t.artist, t.title, t.seconds);
        if (u == null) {
          errs.add('SoundCloud: такой песни нет');
          return false;
        }
        if (cancelled()) return false;
        await player.setAudioSource(AudioSource.uri(u)).timeout(const Duration(seconds: 15));
        return true;
      } catch (e) {
        errs.add('SoundCloud: ${_short(e)}');
        return false;
      }
    }

    final n = YtService.clients.length;
    final order = <Future<bool> Function()>[
      if (_preferSc) sc,
      () => yt(0),
      () => yt(1),
      if (!_preferSc) () async {
        final ok = await sc();
        if (ok) _preferSc = true; // YouTube отказал этому телефону — дальше сразу SoundCloud
        return ok;
      },
      for (var i = 2; i < n; i++) () => yt(i),
    ];
    for (final step in order) {
      if (cancelled()) return false;
      if (await step()) return true;
    }
    throw Exception(errs.join(' · '));
  }

  static String _short(Object? e, [int max = 110]) {
    var s = '$e'.split('\n').first.replaceFirst('Exception: ', '');
    if (s.length > max) s = '${s.substring(0, max)}…';
    return s;
  }

  /// Ссылку на поток следующего трека — заранее: «следующий» включается сразу.
  void _prefetchNext() {
    if (shuffle.value || _preferSc) return;
    final j = index.value + 1;
    if (j < tracks.value.length && !tracks.value[j].isSc) {
      YtService.instance.streamUrl(tracks.value[j].id, economy: Store.instance.economy).ignore();
    }
  }

  int? _nextIndex({bool user = false}) {
    final n = tracks.value.length;
    if (n == 0) return null;
    if (shuffle.value && n > 1) {
      var j = index.value;
      while (j == index.value) {
        j = _rnd.nextInt(n);
      }
      return j;
    }
    final j = index.value + 1;
    if (j < n) return j;
    return (repeat.value == RepeatState.all || user) ? 0 : null;
  }

  void _onCompleted() {
    if (repeat.value == RepeatState.one) {
      player.seek(Duration.zero);
      player.play();
      return;
    }
    final j = _nextIndex();
    if (j != null) {
      _playIndex(j);
    } else {
      player.pause();
      player.seek(Duration.zero);
    }
  }

  void toggleShuffle() => shuffle.value = !shuffle.value;

  void cycleRepeat() {
    repeat.value = RepeatState.values[(repeat.value.index + 1) % RepeatState.values.length];
  }

  Future<void> jumpTo(int i) => _playIndex(i);

  // ── управление (и с экрана блокировки) ──
  @override
  Future<void> play() async {
    if (player.processingState == ProcessingState.idle && current != null) {
      await _playIndex(index.value);
    } else {
      await player.play();
    }
  }

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    final j = _nextIndex(user: true);
    if (j != null) await _playIndex(j);
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3) || index.value <= 0) {
      await player.seek(Duration.zero);
    } else {
      await _playIndex(index.value - 1);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) => _playIndex(index);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  void _broadcast() {
    final playing = player.playing;
    final ps = loading.value
        ? AudioProcessingState.loading
        : const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[player.processingState]!;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: ps,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: index.value < 0 ? null : index.value,
    ));
  }
}

late final EchoesAudio audio;

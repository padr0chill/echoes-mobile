import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import 'store.dart';
import 'offline.dart';
import 'square_cover.dart';
import 'sc.dart';
import 'stream_source.dart';
import 'yt.dart';
import '../i18n.dart';

enum RepeatState { off, all, one }

/// Трек → карточка для экрана блокировки / пункта управления.
extension TrackMedia on Track {
  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        artist: artist,
        duration: seconds > 0 ? duration : null,
        // у видео YouTube — уже обрезанная квадратная (без полос), если готова; иначе сеть
        artUri: SquareCover.instance.ready(this) != null
            ? Uri.file(SquareCover.instance.ready(this)!.path)
            : Uri.parse(art ?? cover),
      );
}

/// Плеер: очередь, фон и экран блокировки (audio_service), звук — потоком (just_audio, без файлов на диске).
class EchoesAudio extends BaseAudioHandler with SeekHandler {
  // iOS: начинать играть сразу, а не копить буфер «на всякий случай» (иначе старт трека — секунды)
  final AudioPlayer player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      darwinLoadControl: DarwinLoadControl(
        automaticallyWaitsToMinimizeStalling: false,
        preferredForwardBufferDuration: Duration(seconds: 20),
      ),
    ),
  );

  final ValueNotifier<List<Track>> tracks = ValueNotifier([]);
  final ValueNotifier<int> index = ValueNotifier(-1);
  final ValueNotifier<bool> loading = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> shuffle = ValueNotifier(false);

  /// «Далее в очереди» (как в Spotify): сколько треков сразу после текущего добавлены вручную —
  /// они играют следующими по порядку, даже при «вперемешку».
  final ValueNotifier<int> upNext = ValueNotifier(0);
  final ValueNotifier<RepeatState> repeat = ValueNotifier(RepeatState.off);

  int _token = 0;
  final _rnd = Random();

  EchoesAudio() {
    index.addListener(_bumpTrackKey);
    tracks.addListener(_bumpTrackKey);
    player.playbackEventStream.listen((_) => _broadcast(), onError: (Object e, StackTrace st) {
      error.value = tr('Поток оборвался — попробуйте ещё раз');
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

  /// Меняется, когда сменился ИГРАЮЩИЙ трек — и при смене номера, и при замене всей очереди
  /// (новый плейлист с той же позиции, «вперемешку» — номер остаётся 0, а трек другой). На него подписаны
  /// мини-плеер, фон, плеер, волна: раньше они слушали только номер и показывали прошлый трек.
  final ValueNotifier<int> trackKey = ValueNotifier(0);
  String? _keyId;

  void _bumpTrackKey() {
    final id = current?.id;
    if (id != _keyId) {
      _keyId = id;
      trackKey.value++;
    }
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
    upNext.value = 0;
    _unshuffled = null;
    tracks.value = List.of(list);
    if (shuffle.value && wave == null && list.length > 1) {
      // «вперемешку»: выбранный трек — первым, остальные — в случайном порядке (очередь это и показывает)
      _shuffleAround(start);
      start = 0;
    }
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

  /// Поставить трек в «Далее в очереди»: first — самым первым («Играть следующим»), иначе — после
  /// уже добавленных («В очередь»). Если трек уже есть в списке — переезжает (не дублируется).
  void _enqueue(Track t, {required bool first}) {
    final l = List.of(tracks.value);
    var cur = index.value;
    if (cur >= 0 && cur < l.length && l[cur] == t) return; // это и так играет
    final old = l.indexOf(t);
    var up = upNext.value;
    if (old >= 0) {
      l.removeAt(old);
      if (old < cur) {
        cur--;
      } else if (old <= cur + up) {
        up--; // был среди «Далее в очереди»
      }
    }
    final at = (first ? cur + 1 : cur + 1 + up).clamp(0, l.length);
    l.insert(at, t);
    index.value = cur;
    tracks.value = l;
    upNext.value = up + 1;
    queue.add(l.map((x) => x.toMediaItem()).toList());
    if (cur < 0) _playIndex(0);
  }

  void playNext(Track t) => _enqueue(t, first: true);

  void addToQueue(Track t) => _enqueue(t, first: false);

  void removeAt(int i) {
    if (i == index.value || i < 0 || i >= tracks.value.length) return;
    final l = List.of(tracks.value)..removeAt(i);
    if (i < index.value) index.value -= 1;
    if (i > index.value && i <= index.value + upNext.value) upNext.value -= 1;
    tracks.value = l;
    queue.add(l.map((x) => x.toMediaItem()).toList());
  }

  /// Перенести трек в очереди (перетаскивание в списке «Далее»).
  void move(int from, int to) {
    final l = List.of(tracks.value);
    if (from < 0 || from >= l.length || from == index.value) return;
    final t = l.removeAt(from);
    to = to.clamp(0, l.length);
    l.insert(to, t);
    var cur = index.value;
    if (from < cur && to >= cur) cur--;
    if (from > cur && to <= cur) cur++;
    index.value = cur;
    tracks.value = l;
    queue.add(l.map((x) => x.toMediaItem()).toList());
  }

  Future<void> _playIndex(int i) async {
    final l = tracks.value;
    if (i < 0 || i >= l.length) return;
    if (player.playing || player.processingState == ProcessingState.completed) _countListened();
    // следующий из «Далее в очереди» — счётчик уменьшается; переход в другое место — очередь «растворяется»
    if (upNext.value > 0 && i != index.value) upNext.value = i == index.value + 1 ? upNext.value - 1 : 0;
    index.value = i;
    final t = l[i];
    final my = ++_token;
    mediaItem.add(t.toMediaItem());
    // экран блокировки: чистая квадратная обложка без полос — как только готова
    SquareCover.instance.get(t).then((f) {
      final m = mediaItem.value;
      if (f != null && m != null && m.id == t.id) mediaItem.add(m.copyWith(artUri: Uri.file(f.path)));
    });
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
      if (my == _token) error.value = tr('Не удалось открыть трек: {0}', [_short(e, 320)]);
    } finally {
      if (my == _token) {
        loading.value = false;
        _broadcast();
      }
    }
  }

  /// Открыть звук трека. YouTube (два способа сразу) и та же песня на SoundCloud ищутся ПАРАЛЛЕЛЬНО —
  /// играет то, что готово первым (YouTube получает небольшую фору); не открылось — второе уже под рукой.
  /// YouTube бывает отказывает телефону («unplayable» — защита от ботов по IP); тогда SoundCloud без форы.
  /// Удачный путь (прокси/напрямую) запоминается.
  bool _useProxy = true; // через прокси надёжнее: googlevideo часто отказывает плееру iOS напрямую
  bool _preferSc = false;

  Future<bool> _openStream(Track t, bool Function() cancelled) async {
    final eco = Store.instance.economy;
    final errs = <String>[];

    // скачан в приложение — играем из памяти телефона, без сети
    final local = Offline.instance.fileFor(t);
    if (local != null) {
      try {
        await player.setAudioSource(AudioSource.file(local.path)).timeout(const Duration(seconds: 10));
        return true;
      } catch (e) {
        errs.add(tr('файл в загрузках: {0}', [_short(e)])); // повреждён — пробуем онлайн
      }
    }

    // трек SoundCloud — звук прямо оттуда (mp3 или HLS)
    if (t.isSc) {
      try {
        final u = (await _resolveSc(t))!;
        if (cancelled()) return false;
        try {
          await player.setAudioSource(AudioSource.uri(u)).timeout(const Duration(seconds: 8));
        } catch (e) {
          // плеер iOS не открыл ссылку — играем из быстро скачанного временного файла
          final f = await Offline.instance.playbackFile(t, url: u);
          if (cancelled()) return false;
          await player.setAudioSource(AudioSource.file(f.path)).timeout(const Duration(seconds: 8));
        }
        return true;
      } catch (e) {
        // SoundCloud не отдал звук (защищённый трек, удалён, ошибка) — та же песня с YouTube
        errs.add('SoundCloud: ${_short(e)}');
        if (cancelled()) return false;
      }
    }
    // отрывок SoundCloud — сначала найти эту песню на YouTube
    var vid = t.id;
    if (t.needsLookup || t.isSc) {
      try {
        vid = await YtService.instance.findSame(t);
      } catch (e) {
        if (t.isSc) throw Exception(tr('{0} · на YouTube не нашлась: {1}', [errs.join(' · '), _short(e)]));
        throw Exception(t.isPreview
            ? tr('на SoundCloud только отрывок, а на YouTube песня не нашлась: {0}', [_short(e)])
            : tr('песня не нашлась на YouTube: {0}', [_short(e)]));
      }
      if (cancelled()) return false;
    }

    // обе площадки — сразу и параллельно
    final ytF = _resolveYt(vid, eco).then<StreamPick?>((p) => p, onError: (Object e) {
      errs.add('YouTube: ${_short(e)}');
      return null;
    });
    final scF = (t.isPreview || t.isSc ? Future<Uri?>.value(null) : _resolveSc(t)).then<Uri?>((u) {
      if (u == null && !t.isPreview && !t.isSc) errs.add(tr('SoundCloud: такой песни нет'));
      return u;
    }, onError: (Object e) {
      errs.add('SoundCloud: ${_short(e)}');
      return null;
    });

    Future<bool> playYt(StreamPick pick) async {
      for (final proxy in [_useProxy, !_useProxy]) {
        if (cancelled()) return false;
        try {
          final src = proxy ? YtProxySource(pick) : AudioSource.uri(pick.url);
          await player.setAudioSource(src).timeout(const Duration(seconds: 8));
          _useProxy = proxy;
          _preferSc = false; // YouTube снова работает
          return true;
        } catch (e) {
          errs.add('YouTube${proxy ? ' прокси' : ''}: ${_short(e)}');
        }
      }
      // ни напрямую, ни через прокси — скачать во временный файл и играть из него
      if (cancelled()) return false;
      try {
        final f = await Offline.instance.playbackFile(t, pick: pick).timeout(const Duration(seconds: 25));
        if (cancelled()) return false;
        await player.setAudioSource(AudioSource.file(f.path)).timeout(const Duration(seconds: 8));
        _preferSc = false;
        return true;
      } catch (e) {
        errs.add(tr('YouTube файл: {0}', [_short(e)]));
      }
      return false;
    }

    Future<bool> playSc(Uri u) async {
      if (cancelled()) return false;
      try {
        await player.setAudioSource(AudioSource.uri(u)).timeout(const Duration(seconds: 8));
        return true;
      } catch (e) {
        errs.add('SoundCloud: ${_short(e)}');
      }
      // плеер iOS не открыл ссылку («unsupported URL») — через временный файл
      if (cancelled()) return false;
      try {
        final f = await Offline.instance.playbackFile(t, url: u).timeout(const Duration(seconds: 20));
        if (cancelled()) return false;
        await player.setAudioSource(AudioSource.file(f.path)).timeout(const Duration(seconds: 8));
        return true;
      } catch (e) {
        errs.add(tr('SoundCloud файл: {0}', [_short(e)]));
        return false;
      }
    }

    // кто первый: YouTube — сразу; SoundCloud — через 0,8 с форы YouTube (оригинал), а если YouTube
    // этому телефону уже отказывал — сразу
    final first = Completer<bool>(); // true — YouTube, false — SoundCloud
    var left = 2;
    void settle() {
      if (--left == 0 && !first.isCompleted) first.complete(true);
    }

    ytF.then((p) {
      if (p != null && !first.isCompleted) first.complete(true);
      settle();
    });
    scF.then((u) {
      if (u != null) {
        if (_preferSc) {
          if (!first.isCompleted) first.complete(false);
        } else {
          Timer(const Duration(milliseconds: 800), () {
            if (!first.isCompleted) first.complete(false);
          });
        }
      }
      settle();
    });
    final ytFirst = await first.future;
    if (cancelled()) return false;
    for (final useYt in [ytFirst, !ytFirst]) {
      if (useYt) {
        final p = await ytF;
        if (p != null && await playYt(p)) return true;
      } else {
        final u = await scF;
        if (u != null && await playSc(u)) {
          // YouTube не смог — дальше SoundCloud без форы (проверка — в фоне, звук уже идёт)
          if (ytFirst) {
            _preferSc = true;
          } else {
            ytF.then((p) => _preferSc = p == null);
          }
          return true;
        }
      }
      if (cancelled()) return false;
    }
    // 2-я попытка: 1) свежая ссылка на то же видео (старая могла «протухнуть» — 403 после смены сети);
    // 2) та же песня другим видео (официальное с YouTube Music / другая заливка — ограничения у них разные)
    YtService.instance.forget(vid);
    final alt = <String>{vid};
    try {
      alt.add(await YtService.instance.findSame(t, exclude: vid).timeout(const Duration(seconds: 8)));
    } catch (_) {}
    for (final v in alt) {
      if (cancelled()) return false;
      try {
        final p = await _resolveYt(v, eco, fresh: true);
        if (await playYt(p)) {
          if (v != vid) errs.clear();
          return true;
        }
      } catch (e) {
        errs.add('YouTube${v == vid ? ' (свежая ссылка)' : ' (другое видео)'}: ${_short(e)}');
      }
    }
    throw Exception(errs.join(' · '));
  }

  /// Поток YouTube: способы 0 и 1 — одновременно (первый удачный), потом остальные по очереди.
  /// Каждый не дольше 7 с — зависший запрос не держит трек.
  Future<StreamPick> _resolveYt(String vid, bool eco, {bool fresh = false}) async {
    Future<StreamPick> one(int i) =>
        YtService.instance.streamWith(vid, i, economy: eco, fresh: fresh).timeout(const Duration(seconds: 7));
    try {
      return await _firstOk([one(0), one(1)]);
    } catch (_) {}
    Object? last;
    for (var i = 2; i < YtService.clients.length; i++) {
      try {
        return await one(i);
      } catch (e) {
        last = e;
      }
    }
    throw Exception(_short(last ?? tr('нет потока')));
  }

  /// Первый успешный из нескольких; все упали — ошибка последнего.
  static Future<T> _firstOk<T>(List<Future<T>> fs) {
    final c = Completer<T>();
    var left = fs.length;
    for (final f in fs) {
      f.then((v) {
        if (!c.isCompleted) c.complete(v);
      }, onError: (Object e) {
        if (--left == 0 && !c.isCompleted) c.completeError(e);
      });
    }
    return c.future;
  }

  /// Та же песня на SoundCloud → ссылка на звук. Запоминается на 10 минут (ссылки SoundCloud временные):
  /// следующий трек готовится заранее и включается мгновенно.
  final _scLinks = <String, (Future<Uri?>, DateTime)>{};
  Future<Uri?> _resolveSc(Track t) {
    final c = _scLinks[t.id];
    if (c != null && DateTime.now().difference(c.$2) < const Duration(minutes: 10)) return c.$1;
    final f = () async {
      if (t.isSc) return ScService.instance.streamUrl(await ScService.instance.track(t.scId));
      final m = await ScService.instance.match(t.artist, t.title, t.seconds);
      return m == null ? null : await ScService.instance.streamUrl(m);
    }();
    _scLinks[t.id] = (f, DateTime.now());
    f.catchError((_) {
      _scLinks.remove(t.id); // ошибка сети — в следующий раз заново
      return null;
    });
    if (_scLinks.length > 60) _scLinks.remove(_scLinks.keys.first);
    return f;
  }

  static String _short(Object? e, [int max = 110]) {
    var s = '$e'.split('\n').first.replaceFirst('Exception: ', '');
    if (s.length > max) s = '${s.substring(0, max)}…';
    return s;
  }

  /// Следующий трек — заранее (обе площадки): «следующий» включается почти сразу.
  void _prefetchNext() {
    final j = index.value + 1;
    if (j >= tracks.value.length) return;
    final n = tracks.value[j];
    if (Offline.instance.has(n)) return;
    if (n.isSc) {
      _resolveSc(n).ignore();
    } else if (n.isYt) {
      if (!n.isPreview) _resolveSc(n).ignore();
      if (!_preferSc) _resolveYt(n.id, Store.instance.economy).ignore();
    }
  }

  int? _nextIndex({bool user = false}) {
    final n = tracks.value.length;
    if (n == 0) return null;
    // добавленные вручную — всегда следующими, даже «вперемешку»
    if (upNext.value > 0 && index.value + 1 < n) return index.value + 1;
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

  /// Порядок до «вперемешку» — чтобы вернуть его, когда перемешивание выключат.
  List<Track>? _unshuffled;

  /// Перемешать очередь вокруг трека i: он — первым, затем «Далее в очереди» (добавленные вручную,
  /// в своём порядке), затем все остальные треки списка в случайном порядке.
  void _shuffleAround(int i) {
    final l = tracks.value;
    if (l.isEmpty) return;
    i = i.clamp(0, l.length - 1);
    _unshuffled = List.of(l);
    final up = upNext.value.clamp(0, l.length - i - 1);
    final head = [l[i], ...l.sublist(i + 1, i + 1 + up)];
    final rest = [...l.sublist(0, i), ...l.sublist(i + 1 + up)]..shuffle(_rnd);
    tracks.value = [...head, ...rest];
    index.value = 0;
    queue.add(tracks.value.map((x) => x.toMediaItem()).toList());
  }

  /// Вперемешку вкл/выкл — как в Spotify: очередь реально перемешивается (и в «Очереди» видно,
  /// что заиграет дальше); выключили — прежний порядок, с того же трека.
  void toggleShuffle() {
    shuffle.value = !shuffle.value;
    final l = tracks.value;
    if (l.length < 2 || nearEnd != null) return; // волна и так случайная
    if (shuffle.value) {
      _shuffleAround(index.value < 0 ? 0 : index.value);
      return;
    }
    final orig = _unshuffled;
    _unshuffled = null;
    if (orig == null) return;
    final cur = current;
    final up = upNext.value.clamp(0, l.length - index.value - 1);
    final queued = index.value >= 0 ? l.sublist(index.value + 1, index.value + 1 + up) : <Track>[];
    // исходный порядок + треки, добавленные уже во время перемешивания (в конец)
    final have = orig.toSet();
    final restored = [...orig, ...l.where((x) => !have.contains(x))]..removeWhere(queued.contains);
    var ci = cur == null ? -1 : restored.indexOf(cur);
    if (ci >= 0) restored.insertAll(ci + 1, queued);
    tracks.value = restored;
    index.value = ci;
    queue.add(restored.map((x) => x.toMediaItem()).toList());
  }

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

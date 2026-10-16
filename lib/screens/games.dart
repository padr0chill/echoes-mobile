import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../glass.dart';
import '../i18n.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/store.dart';
import '../services/ytm_artist.dart';
import '../ui.dart';
import '../widgets.dart';

/// Мини-игры по плейлисту (меню «…» плейлиста).
void openSnake(BuildContext context, List<Track> tracks) => _open(context, SnakeGame(tracks: tracks));
void openGuess(BuildContext context, List<Track> tracks) => _open(context, GuessGame(tracks: tracks));

void _open(BuildContext context, Widget game) {
  final list = game is SnakeGame ? game.tracks : (game as GuessGame).tracks;
  if (list.length < 4) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('Для игры нужно хотя бы 4 трека в плейлисте'))));
    return;
  }
  audio.pause(); // основной плеер молчит, пока идёт игра
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => game));
}

/// Второй плеер для отрывков: один на игру, источники готовятся заранее.
class _Snippets {
  final player = AudioPlayer();
  final _ready = <String, Future<AudioSource?>>{};
  String? playing;
  StreamSubscription<Duration>? _stopSub;

  Future<AudioSource?> prepare(Track t) => _ready[t.id] ??=
      audio.snippetSource(t).then<AudioSource?>((s) => s).timeout(const Duration(seconds: 15)).catchError((_) => null);

  /// Играть трек с позиции from; seconds — остановиться через столько секунд звука (null — играть дальше).
  Future<bool> play(Track t, {Duration from = Duration.zero, double? seconds, bool loop = false}) async {
    final src = await prepare(t);
    if (src == null) return false;
    _stopSub?.cancel();
    try {
      if (playing != t.id) {
        await player.setAudioSource(src, initialPosition: from);
        playing = t.id;
      } else {
        await player.seek(from);
      }
      if (seconds != null) {
        final end = from + Duration(milliseconds: (seconds * 1000).round());
        _stopSub = player.positionStream.listen((p) {
          if (p >= end) {
            player.pause();
            _stopSub?.cancel();
          }
        });
      }
      await player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      unawaited(player.play());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    _stopSub?.cancel();
    await player.pause();
  }

  void dispose() {
    _stopSub?.cancel();
    player.dispose();
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Змейка: ешь треки — у трека рядом с головой играет отрывок
// ════════════════════════════════════════════════════════════════════════════

class SnakeGame extends StatefulWidget {
  final List<Track> tracks;
  const SnakeGame({super.key, required this.tracks});

  @override
  State<SnakeGame> createState() => _SnakeGameState();
}

class _SnakeGameState extends State<SnakeGame> {
  static const cols = 15, rows = 21;
  final _rnd = math.Random();
  final _snip = _Snippets();
  late List<Track> _deck;
  List<math.Point<int>> _snake = [];
  math.Point<int> _dir = const math.Point(1, 0);
  math.Point<int>? _nextDir;
  math.Point<int>? _food;
  Track? _foodTrack;
  final _eaten = <Track>[];
  Timer? _timer;
  bool _over = false, _started = false;
  Track? _near; // трек, чей отрывок играет
  Offset? _swipeFrom;

  @override
  void initState() {
    super.initState();
    _deck = [...widget.tracks]..shuffle(_rnd);
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _snip.dispose();
    super.dispose();
  }

  void _reset() {
    _snake = [const math.Point(5, 10), const math.Point(4, 10), const math.Point(3, 10)];
    _dir = const math.Point(1, 0);
    _nextDir = null;
    _eaten.clear();
    _over = false;
    _started = false;
    _near = null;
    _spawn();
  }

  void _spawn() {
    final free = <math.Point<int>>[
      for (var x = 1; x < cols - 1; x++)
        for (var y = 1; y < rows - 1; y++)
          if (!_snake.contains(math.Point(x, y))) math.Point(x, y)
    ];
    _food = free[_rnd.nextInt(free.length)];
    if (_deck.isEmpty) _deck = [...widget.tracks]..shuffle(_rnd);
    _foodTrack = _deck.removeLast();
    _playFood();
    // следующий трек готовится заранее — после «съел» музыка меняется без паузы
    if (_deck.isNotEmpty) _snip.prepare(_deck.last);
  }

  /// Всё время играет отрывок трека, который сейчас нужно съесть (с середины песни, по кругу).
  void _playFood() {
    final t = _foodTrack!;
    _near = t;
    final from = Duration(seconds: t.seconds > 60 ? (t.seconds * 0.35).round() : 20);
    _snip.play(t, from: from, loop: true);
  }

  void _start() {
    if (_started) return;
    setState(() => _started = true);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    // быстрее с каждым съеденным треком
    _timer = Timer.periodic(Duration(milliseconds: _tickMs), (_) => _tick());
  }

  void _turn(math.Point<int> d) {
    if (_over) return;
    final cur = _nextDir ?? _dir;
    if (cur.x + d.x == 0 && cur.y + d.y == 0) return; // назад нельзя
    _nextDir = d;
    _start();
  }

  void _tick() {
    if (_nextDir != null) {
      _dir = _nextDir!;
      _nextDir = null;
    }
    final head = _snake.first + _dir;
    if (head.x < 0 || head.y < 0 || head.x >= cols || head.y >= rows || _snake.contains(head)) {
      _timer?.cancel();
      HapticFeedback.heavyImpact();
      _snip.stop();
      setState(() => _over = true);
      return;
    }
    final grow = head == _food;
    setState(() {
      _snake = [head, ..._snake];
      if (!grow) _snake.removeLast();
    });
    if (grow) {
      HapticFeedback.mediumImpact();
      _eaten.add(_foodTrack!);
      _spawn();
      _schedule();
    }
  }

  int get _tickMs => (190 - _eaten.length * 6).clamp(85, 190);

  /// Обложка звена змейки: i-е звено после головы — i-й с конца съеденный трек (первые звенья — без обложки).
  Track? _segTrack(int i) {
    final k = _eaten.length - i;
    return i > 0 && k >= 0 && k < _eaten.length ? _eaten[k] : null;
  }

  static const _red = Color(0xFFE22134); // как в Spotify

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final liked = _near != null && Store.instance.isLiked(_near!);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _red,
        // управление — только свайпами по всему экрану: поворот срабатывает, как только палец сдвинулся
        // на ~18 px (не нужно отпускать), в одном жесте можно повернуть несколько раз
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _start,
          onPanStart: (d) => _swipeFrom = d.localPosition,
          onPanUpdate: (d) {
            final from = _swipeFrom;
            if (from == null) return;
            final v = d.localPosition - from;
            if (v.distance < context.u(18)) return;
            _turn(v.dx.abs() > v.dy.abs() ? math.Point(v.dx > 0 ? 1 : -1, 0) : math.Point(0, v.dy > 0 ? 1 : -1));
            _swipeFrom = d.localPosition;
          },
          onPanEnd: (_) => _swipeFrom = null,
          child: SafeArea(
            child: Column(children: [
              // сверху: закрыть · счёт · «+» (трек, который играет, — в «Мне нравится»)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(8), vertical: context.u(4)),
                child: Row(children: [
                  _RoundBtn(icon: Icons.close_rounded, onTap: () => Navigator.pop(context)),
                  Expanded(
                    child: Column(children: [
                      Text(tr('Змейка'),
                          style: const TextStyle(color: white, fontSize: 18, fontWeight: FontWeight.w900)),
                      Text(tr('Съедено: {0}', [_eaten.length]),
                          style: TextStyle(color: white.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  _RoundBtn(
                    icon: liked ? Icons.check_rounded : Icons.add_rounded,
                    filled: liked,
                    onTap: _near == null
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            Store.instance.toggleLike(_near!);
                            setState(() {});
                          },
                  ),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(context.u(10)),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: cols / rows,
                      child: LayoutBuilder(builder: (context, c) {
                        final cell = c.maxWidth / cols;
                        final glide = Duration(milliseconds: _started && !_over ? _tickMs : 0);
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(context.r(10)),
                          ),
                          child: Stack(clipBehavior: Clip.none, children: [
                            if (_food != null && _foodTrack != null)
                              Positioned(
                                left: _food!.x * cell - cell * 0.1,
                                top: _food!.y * cell - cell * 0.1,
                                child: _Food(track: _foodTrack!, size: cell * 1.2),
                              ),
                            // тело: обложки съеденных треков; звенья плавно едут за головой
                            for (var i = _snake.length - 1; i >= 1; i--)
                              AnimatedPositioned(
                                key: ValueKey('seg$i'),
                                duration: glide,
                                left: _snake[i].x * cell + 1,
                                top: _snake[i].y * cell + 1,
                                width: cell - 2,
                                height: cell - 2,
                                child: _Segment(track: _segTrack(i)),
                              ),
                            AnimatedPositioned(
                              key: const ValueKey('head'),
                              duration: glide,
                              left: _snake.first.x * cell,
                              top: _snake.first.y * cell,
                              width: cell,
                              height: cell,
                              child: _Head(dir: _dir),
                            ),
                            if (!_started && !_over)
                              Center(
                                child: Text(tr('Свайпните, чтобы начать'),
                                    style: const TextStyle(color: white, fontSize: 18, fontWeight: FontWeight.w800)),
                              ),
                            if (_over) Positioned.fill(child: _gameOver(context)),
                          ]),
                        );
                      }),
                    ),
                  ),
                ),
              ),
              // что играет
              SizedBox(
                height: context.u(64),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _near == null
                      ? Center(
                          child: Text(tr('Свайпайте в любом месте экрана'),
                              key: const ValueKey('hint'), style: TextStyle(color: white.withValues(alpha: 0.8))))
                      : Padding(
                          key: ValueKey(_near!.id),
                          padding: EdgeInsets.symmetric(horizontal: context.u(20)),
                          child: Row(children: [
                            Cover(track: _near, size: context.u(44), radius: 4),
                            SizedBox(width: context.u(12)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_near!.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: white, fontWeight: FontWeight.w800, fontSize: 15)),
                                  Text(_near!.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: white.withValues(alpha: 0.8))),
                                ],
                              ),
                            ),
                            const Icon(Icons.graphic_eq_rounded, color: white),
                          ]),
                        ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _gameOver(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(context.r(10)),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Игра окончена'),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          SizedBox(height: context.u(6)),
          Text(tr('Съедено: {0}', [_eaten.length]), style: const TextStyle(color: Colors.white70)),
          SizedBox(height: context.u(16)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white),
            onPressed: () => setState(_reset),
            child: Text(tr('Ещё раз'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
          ),
          if (_eaten.isNotEmpty)
            TextButton(
              onPressed: () {
                for (final t in _eaten) {
                  audio.addToQueue(t);
                }
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(tr('Съеденные треки — в очереди ({0})', [_eaten.length]))));
              },
              child: Text(tr('Съеденное — в очередь'), style: const TextStyle(color: Colors.white)),
            ),
        ]),
      );
}

/// Круглая кнопка сверху (✕ / +), как в Spotify.
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  const _RoundBtn({required this.icon, this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) => Material(
        color: filled ? Colors.white : Colors.black.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: context.u(42),
            height: context.u(42),
            child: Icon(icon, color: filled ? const Color(0xFFE22134) : Colors.white),
          ),
        ),
      );
}

/// Голова — белая плашка со стрелкой по направлению движения.
class _Head extends StatelessWidget {
  final math.Point<int> dir;
  const _Head({required this.dir});

  @override
  Widget build(BuildContext context) {
    // стрелка Icons.navigation смотрит вверх → поворот на угол направления
    final turns = dir.x == 1 ? 0.25 : (dir.x == -1 ? 0.75 : (dir.y == 1 ? 0.5 : 0.0));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: AnimatedRotation(
        turns: turns,
        duration: const Duration(milliseconds: 120),
        child: const FittedBox(child: Icon(Icons.navigation_rounded, color: Color(0xFFE22134))),
      ),
    );
  }
}

/// Звено тела: обложка съеденного трека (пока не съедено — полупрозрачный белый квадрат).
class _Segment extends StatelessWidget {
  final Track? track;
  const _Segment({required this.track});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => track == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              )
            : DecoratedBox(
                decoration: const BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))]),
                child: Cover(track: track, size: c.maxWidth, radius: 3),
              ),
      );
}

/// «Еда» — обложка трека, чей отрывок играет: пульсирует.
class _Food extends StatefulWidget {
  final Track track;
  final double size;
  const _Food({required this.track, required this.size});

  @override
  State<_Food> createState() => _FoodState();
}

class _FoodState extends State<_Food> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.1 * _pulse.value,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(2), child: child),
        ),
      ),
      child: Cover(track: widget.track, size: widget.size, radius: 0),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Угадай песню по первым секундам: 1 → 2 → 3 → 4 → 5 → 6 с
// ════════════════════════════════════════════════════════════════════════════

class GuessGame extends StatefulWidget {
  final List<Track> tracks;
  const GuessGame({super.key, required this.tracks});

  @override
  State<GuessGame> createState() => _GuessGameState();
}

class _GuessGameState extends State<GuessGame> {
  static const rounds = 10;
  static const steps = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
  final _rnd = math.Random();
  final _snip = _Snippets();
  late List<Track> _order;
  int _round = 0, _step = 0, _score = 0;
  List<Track> _options = [];
  Track? _picked;
  bool _loading = true, _failed = false;
  final _results = <(Track, int)>[]; // трек, очки

  Track get _answer => _order[_round];
  bool get _revealed => _picked != null || _step >= steps.length;

  @override
  void initState() {
    super.initState();
    _order = ([...widget.tracks]..shuffle(_rnd)).take(rounds).toList();
    _newRound();
  }

  @override
  void dispose() {
    _snip.dispose();
    super.dispose();
  }

  Future<void> _newRound() async {
    final t = _answer;
    setState(() {
      _step = 0;
      _picked = null;
      _options = [t];
      _loading = true;
      _failed = false;
    });
    // следующий раунд готовится заранее
    if (_round + 1 < _order.length) _snip.prepare(_order[_round + 1]);
    final optsF = _sameArtistOptions(t);
    final ok = await _snip.prepare(t) != null;
    final opts = await optsF;
    if (!mounted || _answer != t) return;
    setState(() {
      _options = [t, ...opts]..shuffle(_rnd);
      _loading = false;
      _failed = !ok;
    });
    if (ok) _listen();
  }

  /// Неверные варианты — песни ТОГО ЖЕ исполнителя (так интереснее): сначала из плейлиста, не хватает —
  /// из его дискографии на YouTube Music; совсем нет — случайные из плейлиста.
  final _artistSongs = <String, Future<List<Track>>>{};

  static String _main(String artist) =>
      artist.split(RegExp(r'\s*(,|&| и | x | feat\.? | ft\.? )\s*', caseSensitive: false)).first.trim().toLowerCase();

  static String _key(String title) => title.toLowerCase().replaceAll(RegExp(r'[\(\[].*?[\)\]]'), '').trim();

  Future<List<Track>> _sameArtistOptions(Track t) async {
    final who = _main(t.artist);
    final used = <String>{_key(t.title)};
    final out = <Track>[];
    void add(Iterable<Track> l) {
      for (final x in l) {
        if (out.length >= 3) return;
        if (used.add(_key(x.title))) out.add(x);
      }
    }

    add(widget.tracks.where((x) => x.id != t.id && _main(x.artist) == who).toList()..shuffle(_rnd));
    if (out.length < 3 && who.isNotEmpty) {
      final songs = await (_artistSongs[who] ??= () async {
        try {
          final id = await YtmBrowse.instance.findArtist(who);
          if (id == null) return <Track>[];
          final p = await YtmBrowse.instance.artist(id);
          final all =
              p.songsPlaylist != null ? await YtmBrowse.instance.playlist(p.songsPlaylist!, artist: p.name) : p.top;
          return all.isEmpty ? p.top : all;
        } catch (_) {
          return <Track>[];
        }
      }())
          .timeout(const Duration(seconds: 8), onTimeout: () => <Track>[]);
      add([...songs]..shuffle(_rnd));
    }
    if (out.length < 3) add(widget.tracks.where((x) => x.id != t.id).toList()..shuffle(_rnd));
    return out;
  }

  void _listen() => _snip.play(_answer, seconds: steps[_step.clamp(0, steps.length - 1)]);

  void _skip() {
    if (_revealed) return;
    setState(() => _step++);
    if (_step < steps.length) {
      _listen();
    } else {
      _finishRound(0);
    }
  }

  void _pick(Track t) {
    if (_revealed) return;
    final right = t.id == _answer.id;
    HapticFeedback.mediumImpact();
    setState(() => _picked = t);
    _finishRound(right ? steps.length - _step : 0);
  }

  void _finishRound(int pts) {
    _score += pts;
    _results.add((_answer, pts));
    // показать ответ — песня играет дальше
    _snip.play(_answer, from: Duration.zero);
  }

  void _next() {
    _snip.stop();
    if (_round + 1 >= _order.length) {
      setState(() => _round = _order.length);
      return;
    }
    setState(() => _round++);
    _newRound();
  }

  @override
  Widget build(BuildContext context) {
    final done = _round >= _order.length;
    return Ambient(
      image: !done && _revealed ? _answer.cover : null,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(tr('Угадай песню')),
          actions: [
            Center(
              child: Padding(
                padding: EdgeInsets.only(right: context.u(16)),
                child: Text(tr('Очки: {0}', [_score]),
                    style: TextStyle(fontWeight: FontWeight.w800, color: context.accent)),
              ),
            ),
          ],
        ),
        body: SafeArea(child: done ? _summary(context) : _game(context)),
      ),
    );
  }

  Widget _game(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final t = _answer;
    final right = _picked?.id == t.id;
    return ListView(padding: EdgeInsets.all(context.u(16)), children: [
      Text(tr('Раунд {0} из {1}', [_round + 1, _order.length]),
          textAlign: TextAlign.center, style: TextStyle(color: dim)),
      SizedBox(height: context.u(14)),
      // обложка: скрыта, пока не угадали
      Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _revealed
              ? Cover(key: ValueKey('c${t.id}'), track: t, size: context.u(200), radius: context.u(18), big: true)
              : Container(
                  key: const ValueKey('q'),
                  width: context.u(200),
                  height: context.u(200),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(context.u(18)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Icon(Icons.question_mark_rounded, size: context.u(80), color: context.accent),
                ),
        ),
      ),
      SizedBox(height: context.u(10)),
      if (_revealed)
        Column(children: [
          Text(t.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(t.artist, textAlign: TextAlign.center, style: TextStyle(color: dim)),
          SizedBox(height: context.u(6)),
          Text(
            right ? tr('Угадано за {0} с! +{1}', [steps[_step].round(), steps.length - _step]) : tr('Не угадано'),
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, color: right ? context.accent : Colors.redAccent),
          ),
        ]),
      SizedBox(height: context.u(14)),
      // полоска секунд: 1 2 3 4 5 6
      Row(children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Container(
              height: context.u(8),
              margin: EdgeInsets.symmetric(horizontal: context.u(2)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i <= _step ? context.accent : Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),
      ]),
      SizedBox(height: context.u(4)),
      Row(children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
              child: Text(tr('{0} с', [steps[i].round()]),
                  textAlign: TextAlign.center, style: TextStyle(color: dim, fontSize: 11))),
      ]),
      SizedBox(height: context.u(12)),
      if (_loading)
        Center(child: CircularProgressIndicator(color: context.accent))
      else if (_failed)
        Column(children: [
          Text(tr('Этот трек не загрузился'), textAlign: TextAlign.center),
          TextButton(onPressed: _next, child: Text(tr('Следующий'))),
        ])
      else if (!_revealed)
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _listen,
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
              label: Text(tr('Слушать {0} с', [steps[_step].round()]), style: const TextStyle(color: Colors.black)),
            ),
          ),
          SizedBox(width: context.u(8)),
          OutlinedButton(
            onPressed: _skip,
            child: Text(_step + 1 < steps.length ? tr('+1 секунда') : tr('Сдаюсь')),
          ),
        ]),
      SizedBox(height: context.u(12)),
      for (final o in _options)
        Padding(
          padding: EdgeInsets.only(bottom: context.u(8)),
          child: Material(
            color: _revealed
                ? (o.id == t.id
                    ? context.accent.withValues(alpha: 0.35)
                    : o.id == _picked?.id
                        ? Colors.red.withValues(alpha: 0.3)
                        : Theme.of(context).cardColor)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(context.r(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(context.r(16)),
              onTap: _loading || _failed ? null : () => _pick(o),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(14)),
                child: Text('${o.title} — ${o.artist}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      if (_revealed)
        FilledButton(
          onPressed: _next,
          child: Text(_round + 1 < _order.length ? tr('Дальше') : tr('Итоги'),
              style: const TextStyle(color: Colors.black)),
        ),
    ]);
  }

  Widget _summary(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final max = _order.length * steps.length;
    return ListView(padding: EdgeInsets.all(context.u(16)), children: [
      SizedBox(height: context.u(20)),
      Icon(Icons.emoji_events_rounded, size: context.u(80), color: context.accent),
      Text(tr('{0} из {1} очков', [_score, max]),
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      Text(tr('Угадано песен: {0} из {1}', [_results.where((r) => r.$2 > 0).length, _order.length]),
          textAlign: TextAlign.center, style: TextStyle(color: dim)),
      SizedBox(height: context.u(16)),
      for (final r in _results)
        ListTile(
          leading: Cover(track: r.$1, size: context.u(44), radius: context.u(6)),
          title: Text(r.$1.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(r.$1.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(r.$2 > 0 ? '+${r.$2}' : '—',
              style: TextStyle(fontWeight: FontWeight.w800, color: r.$2 > 0 ? context.accent : dim)),
        ),
      SizedBox(height: context.u(12)),
      FilledButton(
        onPressed: () {
          _snip.stop();
          setState(() {
            _order = ([...widget.tracks]..shuffle(_rnd)).take(rounds).toList();
            _round = 0;
            _score = 0;
            _results.clear();
          });
          _newRound();
        },
        child: Text(tr('Ещё раз'), style: const TextStyle(color: Colors.black)),
      ),
    ]);
  }
}

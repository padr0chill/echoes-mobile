import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../i18n.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/clips.dart';
import '../ui.dart';
import '../widgets.dart';

/// Открыть клип трека (видео YouTube) поверх всего.
void openClip(BuildContext context, Track t) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => ClipScreen(track: t),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

/// Клип: видео со своим звуком (музыка на паузе). Закрыли клип играющего трека — музыка продолжается
/// с той же секунды. Касание — показать/скрыть кнопки; «на весь экран» — повернуть.
class ClipScreen extends StatefulWidget {
  final Track track;
  const ClipScreen({super.key, required this.track});

  @override
  State<ClipScreen> createState() => _ClipScreenState();
}

class _ClipScreenState extends State<ClipScreen> {
  VideoPlayerController? _c;
  Clip? _clip;
  String? _err;
  bool _ui = true;
  bool _full = false;
  bool _fill = false; // заполнить экран (обрезать поля)
  bool _wasPlaying = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _wasPlaying = audio.player.playing && audio.current == widget.track;
    audio.pause();
    _load();
  }

  Future<void> _load() async {
    try {
      final clip = await Clips.instance.find(widget.track);
      if (!mounted) return;
      if (clip == null) {
        setState(() => _err = tr('Клип к этому треку не найден'));
        return;
      }
      setState(() => _clip = clip);
      final url = await Clips.instance.streamUrl(clip.id);
      final c = VideoPlayerController.networkUrl(url);
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      c.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() => _c = c);
      await c.play();
      _autoHide();
    } catch (e) {
      if (mounted) setState(() => _err = tr('Не удалось открыть клип: {0}', ['$e'.replaceFirst('Exception: ', '')]));
    }
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) setState(() => _ui = false);
    });
  }

  Future<void> _setFull(bool v) async {
    setState(() => _full = v);
    if (v) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    final pos = _c?.value.position;
    _c?.dispose();
    if (_full) {
      SystemChrome.setPreferredOrientations([]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    // клип играющего трека — музыка дальше с того же места
    if (_wasPlaying && pos != null && pos > Duration.zero) {
      audio.seek(pos);
      audio.play();
    }
    super.dispose();
  }

  void _quality(BuildContext context) {
    final q = Clips.instance.quality[_clip?.id] ?? '360p';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.check_rounded, color: Colors.white),
            title: Text(q, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            subtitle: Text(tr('Сейчас'), style: const TextStyle(color: Colors.white60)),
          ),
          for (final h in ['720p', '1080p'])
            ListTile(
              enabled: false,
              leading: const Icon(Icons.lock_outline_rounded, color: Colors.white38),
              title: Text(h, style: const TextStyle(color: Colors.white38)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              tr('YouTube отдаёт приложениям без входа в аккаунт только 360p целиком — 720p и выше закрыты '
                  'его защитой (нужен вход). Как только станет можно — включится само.'),
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
        ]),
      ),
    );
  }

  String _t(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final v = c?.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: c == null ? null : () => _setFull(!_full),
        onTap: () {
          setState(() => _ui = !_ui);
          if (_ui) _autoHide();
        },
        child: Stack(children: [
          Center(
            child: c != null && v!.isInitialized
                ? _fill
                    ? ClipRect(
                        child: SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(width: v.size.width, height: v.size.height, child: VideoPlayer(c)),
                        ),
                      ))
                    : AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(c))
                : _err != null
                    ? Padding(
                        padding: EdgeInsets.all(context.u(24)),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Cover(track: widget.track, size: context.u(160), radius: context.u(16), big: true),
                          SizedBox(height: context.u(16)),
                          Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        ]),
                      )
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(color: context.accent),
                        SizedBox(height: context.u(12)),
                        Text(_clip == null ? tr('Ищу клип…') : _clip!.title,
                            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                      ]),
          ),
          if (v != null && v.isBuffering)
            Center(child: CircularProgressIndicator(color: context.accent.withValues(alpha: 0.8))),
          // кнопки
          AnimatedOpacity(
            opacity: _ui || c == null ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !(_ui || c == null),
              child: SafeArea(
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(_clip?.channel ?? widget.track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60)),
                      ]),
                    ),
                    if (c != null)
                      TextButton(
                        onPressed: () => _quality(context),
                        child: Text(Clips.instance.quality[_clip?.id] ?? '360p',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    if (c != null)
                      IconButton(
                        tooltip: _fill ? tr('Целиком') : tr('Заполнить экран'),
                        icon: Icon(_fill ? Icons.fit_screen_rounded : Icons.crop_free_rounded, color: Colors.white),
                        onPressed: () => setState(() => _fill = !_fill),
                      ),
                    if (c != null)
                      IconButton(
                        tooltip: _full ? tr('Свернуть') : tr('На весь экран'),
                        icon:
                            Icon(_full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                        onPressed: () => _setFull(!_full),
                      ),
                  ]),
                  const Spacer(),
                  if (c != null && v!.isInitialized)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                      child: Row(children: [
                        IconButton(
                          iconSize: context.u(44),
                          icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                          onPressed: () {
                            v.isPlaying ? c.pause() : c.play();
                            _autoHide();
                          },
                        ),
                        Text(_t(v.position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: v.position.inMilliseconds.clamp(0, v.duration.inMilliseconds).toDouble(),
                            max: v.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                            onChanged: (x) {
                              c.seekTo(Duration(milliseconds: x.round()));
                              _autoHide();
                            },
                          ),
                        ),
                        Text(_t(v.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

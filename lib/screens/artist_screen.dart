import 'package:flutter/material.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/sc.dart';
import '../services/wave.dart';
import '../ui.dart';
import '../widgets.dart';

/// Открыть страницу исполнителя трека (аккаунт на SoundCloud: у трека SoundCloud — сразу, иначе — поиском по имени).
void openArtist(BuildContext context, Track t) {
  if (t.artist.trim().isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistScreen(name: t.artist, id: t.artistId)));
}

class _ArtistData {
  final ScArtist artist;
  final List<Track> top;
  final List<Track> all;
  const _ArtistData(this.artist, this.top, this.all);
}

/// Страница исполнителя: аватар, подписчики, «Слушать», «Волна по исполнителю», популярное и все треки.
class ArtistScreen extends StatefulWidget {
  final String name;
  final int? id;
  const ArtistScreen({super.key, required this.name, this.id});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<_ArtistData> _f = _load();
  bool _aboutOpen = false;

  Future<_ArtistData> _load() async {
    final sc = ScService.instance;
    final a = widget.id != null ? await sc.artist(widget.id!) : await sc.findArtist(widget.name);
    if (a == null) throw Exception('Исполнитель «${widget.name}» не найден на SoundCloud');
    final r = await Future.wait([sc.artistTop(a.id), sc.artistTracks(a.id)]);
    final top = r[0];
    final topIds = top.map((t) => t.id).toSet();
    return _ArtistData(a, top, r[1].where((t) => !topIds.contains(t.id)).toList());
  }

  String _count(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} млн';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1).replaceAll('.', ',')} тыс.';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ArtistData>(
      future: _f,
      builder: (context, snap) {
        final d = snap.data;
        return Ambient(
          image: d?.artist.avatar,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(children: [
              if (snap.connectionState != ConnectionState.done)
                Center(child: CircularProgressIndicator(color: context.accent))
              else if (d == null)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(context.u(24)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${snap.error ?? 'Не удалось загрузить'}'.replaceFirst('Exception: ', ''),
                          textAlign: TextAlign.center),
                      SizedBox(height: context.u(12)),
                      FilledButton(onPressed: () => setState(() => _f = _load()), child: const Text('Повторить')),
                    ]),
                  ),
                )
              else
                _body(context, d),
              // кнопка «назад» — стеклянная, поверх
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(context.u(8)),
                  child: GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    size: 40,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, _ArtistData d) {
    final a = d.artist;
    final all = [...d.top, ...d.all];
    final sub = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.65);
    return ListView(
      padding: EdgeInsets.only(bottom: context.u(140)),
      children: [
        SizedBox(height: MediaQuery.paddingOf(context).top + context.u(36)),
        Center(
          child: Container(
            padding: EdgeInsets.all(context.u(4)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
              boxShadow: [BoxShadow(color: context.accent.withValues(alpha: 0.35), blurRadius: 40)],
            ),
            child: CircleAvatar(
              radius: context.u(70),
              backgroundColor: Theme.of(context).cardColor,
              backgroundImage: a.avatar != null ? NetworkImage(a.avatar!) : null,
              child: a.avatar == null ? Icon(Icons.person_rounded, size: context.u(64)) : null,
            ),
          ),
        ),
        SizedBox(height: context.u(14)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.u(20)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(a.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.1)),
            ),
            if (a.verified) ...[
              SizedBox(width: context.u(6)),
              Icon(Icons.verified_rounded, color: context.accent, size: context.u(24)),
            ],
          ]),
        ),
        SizedBox(height: context.u(4)),
        Text(
          [
            '${_count(a.followers)} подписчиков',
            if (a.city != null && a.city!.isNotEmpty) a.city!,
          ].join('  ·  '),
          textAlign: TextAlign.center,
          style: TextStyle(color: sub),
        ),
        SizedBox(height: context.u(18)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.u(20)),
          child: Row(children: [
            Expanded(
              child: _GlassAction(
                icon: Icons.play_arrow_rounded,
                label: 'Слушать',
                filled: true,
                onTap: all.isEmpty ? null : () => audio.playList(all, 0),
              ),
            ),
            SizedBox(width: context.u(12)),
            Expanded(
              child: _GlassAction(
                icon: Icons.waves_rounded,
                label: 'Волна',
                onTap: all.isEmpty ? null : () => Wave.instance.startWith(all, a.name),
              ),
            ),
          ]),
        ),
        if (a.about != null && a.about!.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(context.u(20), context.u(16), context.u(20), 0),
            child: GestureDetector(
              onTap: () => setState(() => _aboutOpen = !_aboutOpen),
              child: Text(a.about!,
                  maxLines: _aboutOpen ? 30 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub)),
            ),
          ),
        if (d.top.isNotEmpty) ...[
          const SectionTitle('Популярное'),
          for (var i = 0; i < d.top.length && i < 10; i++)
            TrackTile(track: d.top[i], onTap: () => audio.playList(d.top, i), showArtist: false),
        ],
        if (d.all.isNotEmpty) ...[
          SectionTitle('Все треки · ${d.all.length}'),
          for (var i = 0; i < d.all.length; i++)
            TrackTile(track: d.all[i], onTap: () => audio.playList(d.all, i), showArtist: false),
        ],
        if (all.isEmpty)
          Padding(
            padding: EdgeInsets.all(context.u(24)),
            child:
                const Text('У этого аккаунта нет треков, которые можно слушать целиком', textAlign: TextAlign.center),
          ),
      ],
    );
  }
}

class _GlassAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  const _GlassAction({required this.icon, required this.label, this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final content = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: filled ? Colors.black : null),
      SizedBox(width: context.u(6)),
      Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: filled ? Colors.black : null)),
    ]);
    final h = context.u(50);
    if (filled) {
      return SizedBox(
        height: h,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(shape: const StadiumBorder()),
          child: content,
        ),
      );
    }
    return Glass(
      radius: h / 2,
      shadow: false,
      child: SizedBox(
        height: h,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(customBorder: const StadiumBorder(), onTap: onTap, child: content),
        ),
      ),
    );
  }
}

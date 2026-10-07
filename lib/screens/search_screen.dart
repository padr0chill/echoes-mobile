import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/audio.dart';
import '../services/sc.dart';
import '../services/store.dart';
import '../services/search.dart';
import '../services/text_match.dart';
import '../ui.dart';
import '../widgets.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with AutomaticKeepAliveClientMixin {
  final _c = TextEditingController();
  final _focus = FocusNode();
  List<Track> _results = [];
  List<ScAlbum> _albums = [];
  List<ScArtist> _artists = [];
  bool _busy = false;
  String? _err;
  int _token = 0;
  SearchSource _src = SearchSource.all; // «Все» = YouTube Music + SoundCloud
  String _last = '';

  @override
  bool get wantKeepAlive => true;

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    Store.instance.addSearch(q);
    _last = q;
    final my = ++_token;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      // альбомы — всегда с SoundCloud, параллельно с треками; их ошибка поиску не мешает
      final albumsF = ScService.instance.searchAlbums(q).catchError((_) => <ScAlbum>[]);
      final artistsF = ScService.instance.searchArtists(q).catchError((_) => <ScArtist>[]);
      final r = await SearchService.search(q, _src);
      final al = await albumsF;
      final ar = _relevantArtists(q, await artistsF);
      if (my != _token) return;
      setState(() {
        _results = r;
        _albums = al;
        _artists = ar;
      });
      if (r.isEmpty && al.isEmpty && ar.isEmpty) _err = 'Ничего не нашлось';
    } catch (e) {
      if (my == _token) _err = 'Нет соединения или поиск недоступен';
    } finally {
      if (my == _token && mounted) setState(() => _busy = false);
    }
  }

  /// Исполнители, похожие на запрос (по имени), популярные — выше; остальное — шум поиска.
  static List<ScArtist> _relevantArtists(String q, List<ScArtist> list) {
    final scored = [
      for (final a in list)
        if (TextMatch.similarity(q, a.name) >= 0.5 || TextMatch.similarity(a.name, q) >= 0.5) a
    ]..sort((a, b) {
        final ea = TextMatch.similarity(q, a.name) >= 0.99 ? 1 : 0,
            eb = TextMatch.similarity(q, b.name) >= 0.99 ? 1 : 0;
        if (ea != eb) return eb - ea;
        if (a.verified != b.verified) return a.verified ? -1 : 1;
        return b.followers.compareTo(a.followers);
      });
    return scored.take(8).toList();
  }

  /// Верх списка результатов: исполнители, альбомы, заголовок «Треки».
  List<Widget> _headWidgets() => [
        if (_artists.isNotEmpty) ...[const SectionTitle('Исполнители'), _ArtistRow(artists: _artists)],
        if (_albums.isNotEmpty) ...[const SectionTitle('Альбомы'), AlbumRow(albums: _albums, showArtist: true)],
        if (_results.isNotEmpty && (_albums.isNotEmpty || _artists.isNotEmpty)) const SectionTitle('Треки'),
      ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final st = Store.instance;
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(context.u(16), context.u(12), context.u(16), context.u(6)),
          child: TextField(
            controller: _c,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Песня, исполнитель или альбом',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _c.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _c.clear();
                        _results = [];
                        _albums = [];
                        _artists = [];
                        _err = null;
                      }),
                    ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(context.r(14)), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.symmetric(vertical: context.u(12)),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(context.u(16), 0, context.u(16), context.u(4)),
          child: Wrap(runSpacing: context.u(6), children: [
            for (final s in const [
              (SearchSource.all, 'Все'),
              (SearchSource.ytm, 'YouTube Music'),
              (SearchSource.yt, 'YouTube'),
              (SearchSource.sc, 'SoundCloud'),
            ])
              Padding(
                padding: EdgeInsets.only(right: context.u(8)),
                child: ChoiceChip(
                  label: Text(s.$2),
                  selected: _src == s.$1,
                  onSelected: (_) {
                    setState(() => _src = s.$1);
                    if (_last.isNotEmpty) _search(_last);
                  },
                ),
              ),
          ]),
        ),
        if (_busy) LinearProgressIndicator(minHeight: 2, color: context.accent, backgroundColor: Colors.transparent),
        Expanded(
          child: _results.isNotEmpty || _albums.isNotEmpty || _artists.isNotEmpty
              ? ListView.builder(
                  padding: EdgeInsets.only(bottom: context.u(200)),
                  itemCount: _headWidgets().length + _results.length,
                  itemBuilder: (context, i) {
                    final head = _headWidgets();
                    if (i < head.length) return head[i];
                    final j = i - head.length;
                    return TrackTile(track: _results[j], onTap: () => audio.playList(_results, j));
                  },
                )
              : ListenableBuilder(
                  listenable: st,
                  builder: (context, _) => ListView(children: [
                    if (_err != null)
                      Padding(
                        padding: EdgeInsets.all(context.u(24)),
                        child: Text(_err!, textAlign: TextAlign.center),
                      ),
                    if (st.searches.isNotEmpty)
                      SectionTitle('Вы искали',
                          trailing: TextButton(onPressed: st.clearSearches, child: const Text('Очистить'))),
                    for (final q in st.searches)
                      ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: Text(q),
                        onTap: () {
                          _c.text = q;
                          _search(q);
                        },
                      ),
                    if (st.searches.isEmpty && _err == null)
                      Padding(
                        padding: EdgeInsets.all(context.u(32)),
                        child: Column(children: [
                          Icon(Icons.graphic_eq_rounded, size: context.u(64), color: context.accent),
                          SizedBox(height: context.u(12)),
                          const Text('Найдите любую песню — она заиграет сразу,\nбез скачивания на телефон',
                              textAlign: TextAlign.center),
                        ]),
                      ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

/// Лента исполнителей в поиске: круглое фото, имя, подписчики; нажатие — страница исполнителя.
class _ArtistRow extends StatelessWidget {
  final List<ScArtist> artists;
  const _ArtistRow({required this.artists});

  static String _count(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} млн'
      : n >= 1000
          ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1).replaceAll('.', ',')} тыс.'
          : '$n';

  @override
  Widget build(BuildContext context) {
    final s = context.u(92);
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return SizedBox(
      height: s + context.u(10) + MediaQuery.textScalerOf(context).scale(36),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.u(16)),
        itemCount: artists.length,
        separatorBuilder: (_, __) => SizedBox(width: context.u(14)),
        itemBuilder: (context, i) {
          final a = artists[i];
          return GestureDetector(
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistScreen(name: a.name, id: a.id))),
            child: SizedBox(
              width: s,
              child: Column(children: [
                CircleAvatar(
                  radius: s / 2,
                  backgroundColor: Theme.of(context).cardColor,
                  backgroundImage: a.avatar != null ? NetworkImage(a.avatar!) : null,
                  child: a.avatar == null ? Icon(Icons.person_rounded, size: s * 0.45) : null,
                ),
                SizedBox(height: context.u(6)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                    child: Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (a.verified) Icon(Icons.verified_rounded, size: 14, color: context.accent),
                ]),
                Text('${_count(a.followers)} подп.', maxLines: 1, style: TextStyle(fontSize: 12, color: dim)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

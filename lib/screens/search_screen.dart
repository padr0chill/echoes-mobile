import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/audio.dart';
import '../services/sc.dart';
import '../services/store.dart';
import '../services/search.dart';
import '../ui.dart';
import '../widgets.dart';
import 'album_screen.dart';

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
      final r = await SearchService.search(q, _src);
      final al = await albumsF;
      if (my != _token) return;
      setState(() {
        _results = r;
        _albums = al;
      });
      if (r.isEmpty && al.isEmpty) _err = 'Ничего не нашлось';
    } catch (e) {
      if (my == _token) _err = 'Нет соединения или поиск недоступен';
    } finally {
      if (my == _token && mounted) setState(() => _busy = false);
    }
  }

  int get _head => (_albums.isNotEmpty ? 2 : 0) + (_results.isNotEmpty && _albums.isNotEmpty ? 1 : 0);

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
          child: _results.isNotEmpty || _albums.isNotEmpty
              ? ListView.builder(
                  padding: EdgeInsets.only(bottom: context.u(200)),
                  itemCount: _head + _results.length,
                  itemBuilder: (context, i) {
                    if (_albums.isNotEmpty && i == 0) return const SectionTitle('Альбомы');
                    if (_albums.isNotEmpty && i == 1) return AlbumRow(albums: _albums, showArtist: true);
                    if (_results.isNotEmpty && i == _head - 1) return const SectionTitle('Треки');
                    final j = i - _head;
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

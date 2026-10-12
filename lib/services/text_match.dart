/// Сравнение названий и имён (без Flutter — годится и для утилит): транслитерация кириллицы и доля общих слов.
class TextMatch {
  TextMatch._();

  static const _tr = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'zh', 'з': 'z', 'и': 'i', //
    'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', //
    'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '', //
    'э': 'e', 'ю': 'yu', 'я': 'ya',
  };

  /// Кириллица → латиница (чтобы «Мияги» и «Miyagi» сравнивались).
  static String translit(String s) => s.toLowerCase().split('').map((c) => _tr[c] ?? c).join();

  static List<String> _tokens(String s) => translit(s)
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  /// 0..1: доля общих слов (с транслитерацией); слитно-написанное («theneighbourhood») тоже узнаётся.
  static double similarity(String a, String b) {
    final ta = _tokens(a), tb = _tokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    final ca = ta.join(), cb = tb.join();
    if (ca == cb) return 1;
    final common = ta.where(tb.contains).length;
    final s = common / (ta.length > tb.length ? ta.length : tb.length);
    if (s < 0.5 && (ca.contains(cb) || cb.contains(ca)) && ca.length >= 4 && cb.length >= 4) return 0.75;
    return s;
  }
}

/// Пометки «другой версии» песни в названии: замедленная, ускоренная, концертная, ремикс…
/// Ищутся целыми словами («live», но не «alive»), в любом регистре и в «красивых» шрифтах.
class Versions {
  Versions._();

  /// Почти никогда не ищут намеренно — в поиске убираются совсем.
  static const drop = {'slowed', 'sped', 'nightcore', 'reverb', '8d', 'bassboost', 'pitched', 'tiktok'};

  static final _w = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _tags = <String, RegExp>{
    for (final e in {
      'slowed':
          r'slow(?=\s*[\)\]])|slowed|slow(?:ed)?\s*(?:\+|and|&)\s*reverb|super\s*slow|замедлен\p{L}*|slow\s*version',
      'sped': r'sped\s*-?\s*up|spedup|speed\s*-?\s*up|speedup|sped|fast(?:er)?\s*version|ускорен\p{L}*|hyper\s*speed',
      'nightcore': r'nightcore|daycore',
      'reverb': r'reverb|ревер\p{L}*',
      '8d': r'8\s*d(?:\s*audio)?',
      'bassboost': r'bass\s*-?\s*boost(?:ed)?|басс?\s*буст\p{L}*',
      'pitched': r'pitched(?:\s*(?:up|down))?|pitch\s*(?:up|down)|chopped\s*(?:and|&|n)\s*screwed',
      'tiktok': r'tik\s*-?\s*tok(?:\s*version)?',
      'live':
          r'live|концерт\p{L}*|concert|живое\s+выступлени\p{L}*|live\s+at|on\s+stage|unplugged|tour\s+\d{4}|festival|фестивал\p{L}*',
      'remix': r'remix|rmx|ремикс\p{L}*|bootleg|vip\s*mix',
      'cover': r'cover|кавер\p{L}*|перепев\p{L}*|tribute',
      'karaoke': r'karaoke|караоке|минус\p{L}*|minus',
      'instrumental': r'instrumental|инструментал\p{L}*|beat\s*only',
      'acoustic': r'acoustic|акустик\p{L}*|piano\s*version',
      'mashup': r'mashup|mash\s*up|мэшап\p{L}*',
      'snippet': r'snippet|snip|preview|teaser|превью|отрывок|сниппет',
      'extended': r'extended|reanimation|remake',
    }.entries)
      e.key: RegExp(r'(?<![\p{L}\p{N}])(?:' + e.value + r')(?![\p{L}\p{N}])', unicode: true, caseSensitive: false),
  };

  /// «Красивые» шрифты (𝒔𝒍𝒐𝒘𝒆𝒅, ｓｌｏｗｅｄ) → обычные буквы.
  static String plain(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x1D400 && r <= 0x1D6A3) {
        final i = (r - 0x1D400) % 52;
        b.writeCharCode(i < 26 ? 0x41 + i : 0x61 + i - 26);
      } else if (r >= 0x1D7CE && r <= 0x1D7FF) {
        b.writeCharCode(0x30 + (r - 0x1D7CE) % 10);
      } else if (r >= 0xFF01 && r <= 0xFF5E) {
        b.writeCharCode(r - 0xFEE0);
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// Какие пометки есть в тексте (исполнитель + название).
  static Set<String> of(String text) {
    final t = plain(text);
    if (!_w.hasMatch(t)) return const {};
    return {
      for (final e in _tags.entries)
        if (e.value.hasMatch(t)) e.key
    };
  }

  /// Пометки, которых нет в запросе (если «slowed» искали сами — это не лишнее).
  static Set<String> extra(String text, String query) => of(text).difference(of(query));
}

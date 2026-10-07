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

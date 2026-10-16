import 'package:echoes_mobile/screens/artist_screen.dart';
import 'package:echoes_mobile/services/auto_lyrics.dart';
import 'package:flutter_test/flutter_test.dart';

HeardWord w(String t, double s) => (text: t, start: s, dur: 0.3);

void main() {
  test('строки получают время первого услышанного слова, пропуски — между соседями', () {
    final lines = ['Первая строка про дождь', 'вторая строка которую не слышно', 'третья строка про ночь'];
    final heard = [
      w('первая', 10),
      w('строка', 10.4),
      w('про', 10.8),
      w('дождя', 11.1), // распознано с ошибкой — всё равно совпадает
      w('третья', 30),
      w('строка', 30.4),
      w('ночь', 31),
    ];
    final out = AutoLyrics.align(lines, heard, 200);
    expect(out.length, 3);
    expect(out[0].at.inMilliseconds, 10000);
    expect(out[2].at.inMilliseconds, 30000);
    expect(out[1].at > out[0].at && out[1].at < out[2].at, isTrue);
  });

  test('без текста — строки из распознанного по паузам', () {
    final out = AutoLyrics.group([w('раз', 1), w('два', 1.3), w('три', 5), w('четыре', 5.3)]);
    expect(out.map((l) => l.text), ['Раз два', 'Три четыре']);
    expect(out[1].at.inMilliseconds, 5000);
  });

  test('похожие слова с ошибками распознавания', () {
    expect(AutoLyrics.same('ебашу', 'ебошу'), isTrue);
    expect(AutoLyrics.same('я', 'и'), isFalse);
  });

  test('фиты делятся на отдельных исполнителей', () {
    expect(splitArtists('Платина, OG Buda & Mayot'), ['Платина', 'OG Buda', 'Mayot']);
    expect(splitArtists('Travis Scott feat. Drake'), ['Travis Scott', 'Drake']);
    expect(splitArtists('Big Baby Tape x Kizaru'), ['Big Baby Tape', 'Kizaru']);
    expect(splitArtists('Скриптонит'), ['Скриптонит']);
  });
}

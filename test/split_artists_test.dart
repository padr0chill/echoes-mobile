import 'package:echoes_mobile/screens/artist_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('фиты делятся на отдельных исполнителей', () {
    expect(splitArtists('Платина, OG Buda & Mayot'), ['Платина', 'OG Buda', 'Mayot']);
    expect(splitArtists('Travis Scott feat. Drake'), ['Travis Scott', 'Drake']);
    expect(splitArtists('Big Baby Tape x Kizaru'), ['Big Baby Tape', 'Kizaru']);
    expect(splitArtists('Скриптонит'), ['Скриптонит']);
  });
}

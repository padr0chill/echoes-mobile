@Tags(['network'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:echoes_mobile/services/square_cover.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Обрезка полос у превью YouTube (до/после — в папку out): flutter test test/square_cover_test.dart --run-skipped
void main() {
  for (final id in ['S9oa-5CQdf0', 'X9N-3-oEMK0', 'B5wofUHNaGg', 'nftMiMczZFY', 'ok-8cAbeGeQ', 'SbNe5ahuUa0', 'JGqA7Evm0y0']) {
    test(id, () async {
      final r = await http.get(Uri.parse('https://i.ytimg.com/vi/$id/maxresdefault.jpg'));
      final bytes = r.statusCode == 200 && r.bodyBytes.length > 3000
          ? r.bodyBytes
          : (await http.get(Uri.parse('https://i.ytimg.com/vi/$id/hqdefault.jpg'))).bodyBytes;
      final png = await SquareCover.squarePng(bytes);
      expect(png, isNotNull);
      final img = (await (await ui.instantiateImageCodec(png!)).getNextFrame()).image;
      expect(img.width, img.height); // квадрат
      final dir = Directory(Platform.environment['OUT'] ?? 'build/square_out')..createSync(recursive: true);
      File('${dir.path}/${id}_before.jpg').writeAsBytesSync(bytes);
      File('${dir.path}/${id}_after.png').writeAsBytesSync(png);
      // ignore: avoid_print
      print('$id: ${img.width}×${img.height}');
    });
  }
}
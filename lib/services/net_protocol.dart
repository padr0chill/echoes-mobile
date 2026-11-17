import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip340/bip340.dart' as schnorr;
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/digests/sha3.dart';

typedef NetJson = Map<String, dynamic>;

const _base32 = 'abcdefghijklmnopqrstuvwxyz234567';
final _scalarOrder = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);
final _random = Random.secure();
final _keyPattern = RegExp(r'^[a-f0-9]{64}$');
final _sigPattern = RegExp(r'^[a-f0-9]{128}$');

NetJson netObject(Object? value) => value is NetJson ? value : const {};

NetJson netDecode(String value) {
  try {
    return netObject(jsonDecode(value));
  } on FormatException {
    return const {};
  }
}

String netText(Object? value, int length) {
  if (value is! String) return '';
  return String.fromCharCodes(value.trim().runes.take(length));
}

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _onionBytes(List<int> publicKey) {
  final sum = SHA3Digest(256).process(
    Uint8List.fromList([...ascii.encode('.onion checksum'), ...publicKey, 3]),
  );
  return Uint8List.fromList([...publicKey, sum[0], sum[1], 3]);
}

String _encodeOnion(List<int> publicKey) {
  final bytes = _onionBytes(publicKey);
  final code = StringBuffer();
  var buffer = 0, bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      code.write(_base32[(buffer >> bits) & 31]);
    }
    buffer &= (1 << bits) - 1;
  }
  return code.toString();
}

List<int>? _decodeOnion(String code) {
  if (code.length != 56) return null;
  final bytes = <int>[];
  var buffer = 0, bits = 0;
  for (var i = 0; i < code.length; i++) {
    final index = _base32.indexOf(code[i]);
    if (index < 0) return null;
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add(buffer >> bits);
      buffer &= (1 << bits) - 1;
    }
  }
  final publicKey = bytes.sublist(0, 32);
  final expected = _onionBytes(publicKey);
  return bytes[32] == expected[32] &&
          bytes[33] == expected[33] &&
          bytes[34] == 3
      ? publicKey
      : null;
}

class NetIdentity {
  NetIdentity._(this.onion, this.pubkey, this._secret, this._linkSignature);

  final String onion;
  final String pubkey;
  final String _secret;
  final String _linkSignature;

  static Uint8List parseSeed(String input) {
    var value = input.replaceFirst('\uFEFF', '').trim();
    if (value.length > 2048) throw const FormatException('Invalid ECHOES key');
    if (value.startsWith('{')) {
      final file = netDecode(value);
      final seed = file['seed'];
      if (file['v'] != 1 || seed is! String) {
        throw const FormatException('Invalid ECHOES key');
      }
      value = seed.trim();
    }
    // An onion friend code is public and must never be accepted as a secret.
    if (!RegExp(r'^[A-Za-z0-9+/]{43}=?$').hasMatch(value)) {
      throw const FormatException('Invalid ECHOES key');
    }
    final seed = base64Decode(base64.normalize(value));
    if (seed.length != 32) throw const FormatException('Invalid ECHOES key');
    return seed;
  }

  static Future<NetIdentity> fromSeed(Uint8List seed) async {
    final digest = sha256.convert([
      ...ascii.encode('echoes-nostr-v1|'),
      ...seed,
    ]);
    final scalar =
        BigInt.parse(digest.toString(), radix: 16) %
            (_scalarOrder - BigInt.one) +
        BigInt.one;
    final secret = scalar.toRadixString(16).padLeft(64, '0');
    final pubkey = schnorr.getPublicKey(secret);
    final algorithm = Ed25519();
    final pair = await algorithm.newKeyPairFromSeed(seed);
    final publicKey = await pair.extractPublicKey();
    final link = await algorithm.sign(
      ascii.encode('echoes-nostr-link|$pubkey'),
      keyPair: pair,
    );
    return NetIdentity._(
      _encodeOnion(publicKey.bytes),
      pubkey,
      secret,
      base64Encode(link.bytes),
    );
  }

  Future<NetJson> event(
    int kind,
    String content,
    List<List<String>> tags, {
    int work = 0,
  }) => _signEvent(_secret, pubkey, kind, content, [
    ...tags,
    ['echoes-onion', onion, _linkSignature],
  ], work);
}

String _eventId(NetJson event) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          0,
          event['pubkey'],
          event['created_at'],
          event['kind'],
          event['tags'],
          event['content'],
        ]),
      ),
    )
    .toString();

int netWork(String id) {
  var bits = 0;
  for (var i = 0; i < id.length; i++) {
    final digit = int.parse(id[i], radix: 16);
    if (digit != 0) return bits + 4 - digit.bitLength;
    bits += 4;
  }
  return bits;
}

String netTag(NetJson event, String name) {
  final tags = event['tags'];
  if (tags is! List) return '';
  for (final tag in tags) {
    if (tag is List && tag.length >= 2 && tag.first == name && tag[1] is String) {
      return tag[1] as String;
    }
  }
  return '';
}

Future<String> netLinkedOnion(NetJson event) async {
  final pubkey = event['pubkey'];
  final tags = event['tags'];
  if (pubkey is! String || tags is! List) return '';
  for (final tag in tags) {
    if (tag is! List ||
        tag.length < 3 ||
        tag[0] != 'echoes-onion' ||
        tag[1] is! String ||
        tag[2] is! String) {
      continue;
    }
    final code = tag[1] as String;
    final publicKey = _decodeOnion(code);
    if (publicKey == null) continue;
    try {
      final signature = base64Decode(tag[2] as String);
      if (signature.length == 64 &&
          await Ed25519().verify(
            ascii.encode('echoes-nostr-link|$pubkey'),
            signature: Signature(
              signature,
              publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
            ),
          )) {
        return code;
      }
    } catch (_) {
      // Bad links do not grant an Echoes identity.
    }
  }
  return '';
}

bool netEventShape(NetJson event) {
  final id = event['id'], pub = event['pubkey'], sig = event['sig'];
  final kind = event['kind'],
      time = event['created_at'],
      content = event['content'],
      tags = event['tags'];
  return id is String &&
      _keyPattern.hasMatch(id) &&
      pub is String &&
      _keyPattern.hasMatch(pub) &&
      sig is String &&
      _sigPattern.hasMatch(sig) &&
      kind is int &&
      time is int &&
      time >= 0 &&
      time <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600 &&
      content is String &&
      content.length <= 120000 &&
      tags is List &&
      tags.length <= 256 &&
      tags.every(
        (t) => t is List && t.isNotEmpty && t.every((s) => s is String),
      );
}

bool netVerify(NetJson event) {
  if (!netEventShape(event)) return false;
  try {
    final id = event['id'] as String;
    return _eventId(event) == id &&
        schnorr.verify(event['pubkey'] as String, id, event['sig'] as String);
  } catch (_) {
    return false;
  }
}

Future<NetJson> _signEvent(
  String secret,
  String pubkey,
  int kind,
  String content,
  List<List<String>> tags,
  int work,
) => Isolate.run(() {
  final event = <String, dynamic>{
    'pubkey': pubkey,
    'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'kind': kind,
    'tags': tags,
    'content': content,
  };
  var id = _eventId(event);
  if (work > 0) {
    final nonce = ['nonce', '0', '$work'];
    tags.add(nonce);
    for (var i = 0; ; i++) {
      nonce[1] = '$i';
      id = _eventId(event);
      if (netWork(id) >= work) break;
    }
  }
  return event
    ..['id'] = id
    ..['sig'] = schnorr.sign(
      secret,
      id,
      _hex(List.generate(32, (_) => _random.nextInt(256))),
    );
});

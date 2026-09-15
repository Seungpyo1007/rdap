/// Encodes one Unicode domain label with Punycode (RFC 3492), without the
/// `xn--` prefix: `bücher` becomes `bcher-kva`.
String punycodeEncode(String label) {
  final codePoints = label.runes.toList(growable: false);
  final output = StringBuffer();
  for (final codePoint in codePoints) {
    if (codePoint < 0x80) output.writeCharCode(codePoint);
  }
  final basicLength = output.length;
  if (basicLength > 0) output.write('-');

  var handled = basicLength;
  var n = _initialN;
  var delta = 0;
  var bias = _initialBias;
  while (handled < codePoints.length) {
    final next = codePoints
        .where((codePoint) => codePoint >= n)
        .reduce((a, b) => a < b ? a : b);
    delta += (next - n) * (handled + 1);
    n = next;
    for (final codePoint in codePoints) {
      if (codePoint < n) delta++;
      if (codePoint != n) continue;
      var q = delta;
      for (var k = _base; ; k += _base) {
        final t = k <= bias
            ? _tMin
            : k >= bias + _tMax
            ? _tMax
            : k - bias;
        if (q < t) break;
        output.writeCharCode(_digit(t + (q - t) % (_base - t)));
        q = (q - t) ~/ (_base - t);
      }
      output.writeCharCode(_digit(q));
      bias = _adapt(delta, handled + 1, first: handled == basicLength);
      delta = 0;
      handled++;
    }
    delta++;
    n++;
  }
  return output.toString();
}

const _base = 36;
const _tMin = 1;
const _tMax = 26;
const _skew = 38;
const _damp = 700;
const _initialBias = 72;
const _initialN = 0x80;

/// Digits 0-25 are `a`-`z`, 26-35 are `0`-`9`.
int _digit(int value) => value < 26 ? 0x61 + value : 0x16 + value;

int _adapt(int delta, int points, {required bool first}) {
  delta = first ? delta ~/ _damp : delta ~/ 2;
  delta += delta ~/ points;
  var k = 0;
  while (delta > ((_base - _tMin) * _tMax) ~/ 2) {
    delta ~/= _base - _tMin;
    k += _base;
  }
  return k + ((_base - _tMin + 1) * delta) ~/ (delta + _skew);
}

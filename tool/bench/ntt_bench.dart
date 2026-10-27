// ignore_for_file: avoid_print
import 'package:pqlattice/pqlattice.dart';

/// Microbench: ML-KEM NTT + basemul + invNTT (accelerated path).
/// Run: `dart run tool/bench/ntt_bench.dart`
/// Prefer `dart compile exe tool/bench/ntt_bench.dart` for AOT numbers.
void main() {
  final ring = RingParams.mlKem;
  final ntt = NttEngine(ring, params: NttParams.mlKem());
  final a = Poly.fromCoeffs(
    ring,
    List<int>.generate(256, (i) => (i * 17 + 3) % 3329),
  );
  final b = Poly.fromCoeffs(
    ring,
    List<int>.generate(256, (i) => (i * 31 + 5) % 3329),
  );

  // Warmup
  for (var i = 0; i < 200; i++) {
    final ah = ntt.forward(a);
    final bh = ntt.forward(b);
    final ch = Basemul.mlKemPairs(ah, bh, ring);
    ntt.inverse(ch);
  }

  const rounds = 2000;
  final sw = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    final ah = ntt.forward(a);
    final bh = ntt.forward(b);
    final ch = Basemul.mlKemPairs(ah, bh, ring);
    ntt.inverse(ch);
  }
  sw.stop();
  final us = sw.elapsedMicroseconds / rounds;
  print(
    'ML-KEM mul via NTT+basemul+inv: ${us.toStringAsFixed(1)} µs/op ($rounds iters)',
  );

  // In-place path
  final x = a.clone();
  final y = b.clone();
  sw
    ..reset()
    ..start();
  for (var i = 0; i < rounds; i++) {
    x.coeffs.setAll(0, a.coeffs);
    y.coeffs.setAll(0, b.coeffs);
    ntt.forwardInPlace(x);
    ntt.forwardInPlace(y);
    Basemul.mlKemPairsInPlace(x, x, y);
    ntt.inverseInPlace(x);
  }
  sw.stop();
  print(
    'ML-KEM in-place mul path: ${(sw.elapsedMicroseconds / rounds).toStringAsFixed(1)} µs/op',
  );
}

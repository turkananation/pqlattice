import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:pqlattice/src/simd/ntt_simd_int32x4.dart';
import 'package:test/test.dart';

/// SIMD-shaped pointwise must be residue-identical to the scalar Barrett
/// pointwise path for every shipped profile. Exercises the 4-wide kernel
/// shape directly (bypassing SimdCapability, which stays false until AOT
/// parity is recorded — see doc/SIMD.md).
void main() {
  final cases = <(RingParams, int Function(Random))>[
    (RingParams.mlKem, (r) => r.nextInt(3329)),
    (RingParams.mlDsa, (r) => r.nextInt(8380417)),
    (RingParams.fnDsa512, (r) => r.nextInt(12289)),
    (RingParams.fnDsa1024, (r) => r.nextInt(12289)),
  ];

  for (final c in cases) {
    final ring = c.$1;
    final sample = c.$2;
    group('SIMD pointwise parity ${ring.name}', () {
      test('random polys: SIMD shape == scalar basemul', () {
        final rnd = Random(0xBEEF ^ ring.q);
        final a = Poly.fromCoeffs(
          ring,
          List<int>.generate(ring.n, (_) => sample(rnd)),
        );
        final b = Poly.fromCoeffs(
          ring,
          List<int>.generate(ring.n, (_) => sample(rnd)),
        );

        final scalar = Basemul.pointwise(a, b, ring);
        final simdOut = Poly.zero(ring);
        NttSimdInt32x4.pointwiseInPlace(simdOut, a, b, ring);

        expect(
          simdOut.coeffs,
          scalar.coeffs,
          reason: '${ring.name} random parity',
        );
      });

      test('boundary polys: SIMD shape == scalar basemul', () {
        final n = ring.n;
        final q = ring.q;
        final cases = <List<int>>[
          List<int>.filled(n, 0),
          List<int>.filled(n, 1),
          List<int>.generate(n, (i) => i % q),
          List<int>.generate(n, (i) => (q - 1 - i) % q),
        ];
        for (final vals in cases) {
          final a = Poly.fromCoeffs(ring, vals);
          final b = Poly.fromCoeffs(ring, vals.reversed.toList());
          final scalar = Basemul.pointwise(a, b, ring);
          final simdOut = Poly.zero(ring);
          NttSimdInt32x4.pointwiseInPlace(simdOut, a, b, ring);
          expect(
            simdOut.coeffs,
            scalar.coeffs,
            reason: '${ring.name} boundary parity',
          );
        }
      });

      test('n not divisible by 4: tail lane handled', () {
        // All profiles have n a power of two >= 256, so divisible by 4;
        // this guards the tail loop against future odd-length rings.
        final ringOdd = RingParams(q: 17, n: 6, name: 'odd');
        // Barrett not ready for q=17 → both paths use ModQ.reduce (%).
        final rnd = Random(7);
        final a = Poly.fromCoeffs(
          ringOdd,
          List<int>.generate(6, (_) => rnd.nextInt(17)),
        );
        final b = Poly.fromCoeffs(
          ringOdd,
          List<int>.generate(6, (_) => rnd.nextInt(17)),
        );
        final scalar = Basemul.pointwise(a, b, ringOdd);
        final simdOut = Poly.zero(ringOdd);
        NttSimdInt32x4.pointwiseInPlace(simdOut, a, b, ringOdd);
        expect(simdOut.coeffs, scalar.coeffs, reason: 'odd-length tail parity');
      });
    });
  }
}

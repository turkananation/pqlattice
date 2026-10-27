import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

/// Linearity: forward(a + b) ≡ forward(a) + forward(b) (mod q),
/// plus inverse linearity. Deterministic seeds per profile.
///
/// ML-KEM uses the incomplete NTT; ML-DSA / FN-DSA use complete-style NTT.
/// For each profile the forward map is linear over Z_q regardless of shape.
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
    final seed = 0x5EED ^ ring.q;

    group('linearity ${ring.name}', () {
      final rnd = Random(seed);
      final a = Poly.fromCoeffs(
        ring,
        List<int>.generate(ring.n, (_) => sample(rnd)),
      );
      final b = Poly.fromCoeffs(
        ring,
        List<int>.generate(ring.n, (_) => sample(rnd)),
      );

      test('forward(a + b) ≡ forward(a) + forward(b)', () {
        final engine = NttEngine(ring);
        final sum = Poly.zero(ring);
        PolyOps.addInto(sum, a, b);

        final lhs = engine.forward(sum);
        final rhs = Poly.zero(ring);
        PolyOps.addInto(rhs, engine.forward(a), engine.forward(b));

        for (var i = 0; i < ring.n; i++) {
          expect(
            lhs.coeffs[i] % ring.q,
            rhs.coeffs[i] % ring.q,
            reason: 'coeff $i',
          );
        }
      });

      test('forward(a - b) ≡ forward(a) - forward(b)', () {
        final engine = NttEngine(ring);
        final diff = Poly.zero(ring);
        PolyOps.subInto(diff, a, b);

        final lhs = engine.forward(diff);
        final rhs = Poly.zero(ring);
        PolyOps.subInto(rhs, engine.forward(a), engine.forward(b));

        for (var i = 0; i < ring.n; i++) {
          expect(
            lhs.coeffs[i] % ring.q,
            rhs.coeffs[i] % ring.q,
            reason: 'coeff $i',
          );
        }
      });

      test('inverse(aHat + bHat) ≡ inverse(aHat) + inverse(bHat)', () {
        final engine = NttEngine(ring);
        final ah = engine.forward(a);
        final bh = engine.forward(b);

        final sumHat = Poly.zero(ring);
        PolyOps.addInto(sumHat, ah, bh);

        final lhs = engine.inverse(sumHat);
        final rhs = Poly.zero(ring);
        PolyOps.addInto(rhs, engine.inverse(ah), engine.inverse(bh));

        for (var i = 0; i < ring.n; i++) {
          expect(
            lhs.coeffs[i] % ring.q,
            rhs.coeffs[i] % ring.q,
            reason: 'coeff $i',
          );
        }
      });

      test('zero maps to zero', () {
        final engine = NttEngine(ring);
        final z = Poly.zero(ring);
        final h = engine.forward(z);
        expect(h.coeffs.every((c) => c == 0), isTrue);
        final back = engine.inverse(h);
        expect(back.coeffs.every((c) => c == 0), isTrue);
      });

      test('identity basis e_i round-trips (exhaustive over n)', () {
        final engine = NttEngine(ring);
        for (var i = 0; i < ring.n; i++) {
          final e = Poly.zero(ring);
          e.coeffs[i] = 1;
          final back = engine.inverse(engine.forward(e));
          expect(back.coeffs[i] % ring.q, 1 % ring.q, reason: 'e_$i coeff $i');
          for (var j = 0; j < ring.n; j++) {
            if (j != i) {
              expect(back.coeffs[j] % ring.q, 0, reason: 'e_$i coeff $j');
            }
          }
        }
      });
    });
  }
}

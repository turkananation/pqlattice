import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

/// FN-DSA integer NTT roundtrip and table integrity (q=12289).
///
/// Tables: ψ=49 (n=512), ψ=7 (n=1024); invN = n^{-1} mod q.
/// FIPS 206 is draft; these exercise Falcon-compatible integer NTT only.
void main() {
  group('FN-DSA-512 NTT', () {
    final ring = RingParams.fnDsa512;
    final params = NttParams.fnDsa512();
    final ntt = NttEngine(ring, params: params);
    final nttRef = NttEngine(ring, params: params, mode: KernelMode.reference);

    test('zeta table length and psi properties', () {
      expect(params.zetas.length, 512);
      expect(params.invNScale, 12265); // 512^{-1} mod 12289
      expect(params.zetas[0], 1);
      // ψ=49: 49^512 ≡ -1, 49^1024 ≡ 1 (checked offline; table starts with 1)
    });

    test('forward+inverse roundtrip (accelerated)', () {
      final a = Poly.zero(ring);
      for (var i = 0; i < ring.n; i++) {
        a.coeffs[i] = (i * 17 + 3) % ring.q;
      }
      final hat = ntt.forward(a);
      final back = ntt.inverse(hat);
      for (var i = 0; i < ring.n; i++) {
        expect(
          back.coeffs[i] % ring.q,
          a.coeffs[i] % ring.q,
          reason: 'coeff $i',
        );
      }
    });

    test('accelerated matches reference residues', () {
      final a = Poly.zero(ring);
      for (var i = 0; i < ring.n; i++) {
        a.coeffs[i] = (i * 31 + 7) % ring.q;
      }
      final hatA = ntt.forward(a);
      final hatR = nttRef.forward(a);
      for (var i = 0; i < ring.n; i++) {
        expect(hatA.coeffs[i] % ring.q, hatR.coeffs[i] % ring.q);
      }
      final backA = ntt.inverse(hatA);
      final backR = nttRef.inverse(hatR);
      for (var i = 0; i < ring.n; i++) {
        expect(backA.coeffs[i] % ring.q, backR.coeffs[i] % ring.q);
      }
    });

    test('in-place APIs', () {
      final a = Poly.zero(ring);
      for (var i = 0; i < ring.n; i++) {
        a.coeffs[i] = (i * 5) % ring.q;
      }
      final clone = a.clone();
      ntt.forwardInPlace(clone);
      ntt.inverseInPlace(clone);
      for (var i = 0; i < ring.n; i++) {
        expect(clone.coeffs[i] % ring.q, a.coeffs[i] % ring.q);
      }
    });
  });

  group('FN-DSA-1024 NTT', () {
    final ring = RingParams.fnDsa1024;
    final params = NttParams.fnDsa1024();
    final ntt = NttEngine(ring, params: params);

    test('zeta table and invN', () {
      expect(params.zetas.length, 1024);
      expect(params.invNScale, 12277); // 1024^{-1} mod 12289
      expect(params.zetas[0], 1);
    });

    test('forward+inverse roundtrip', () {
      final a = Poly.zero(ring);
      for (var i = 0; i < ring.n; i++) {
        a.coeffs[i] = (i * 13 + 11) % ring.q;
      }
      final hat = ntt.forward(a);
      final back = ntt.inverse(hat);
      for (var i = 0; i < ring.n; i++) {
        expect(
          back.coeffs[i] % ring.q,
          a.coeffs[i] % ring.q,
          reason: 'coeff $i',
        );
      }
    });
  });

  group('FN-DSA NTT × pointwise basemul vs schoolbook (L3)', () {
    for (final (label, ring) in [
      ('FN-DSA-512', RingParams.fnDsa512),
      ('FN-DSA-1024', RingParams.fnDsa1024),
    ]) {
      test('$label random polys agree with schoolbook negacyclic', () {
        final ntt = NttEngine(ring);
        final rnd = Random(ring.n ^ ring.q);
        final a = Poly.fromCoeffs(
          ring,
          List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
        );
        final b = Poly.fromCoeffs(
          ring,
          List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
        );

        final school = RingMul.schoolbookNegacyclic(a, b, ring);
        final cHat = Basemul.pointwise(ntt.forward(a), ntt.forward(b), ring);
        final c = ntt.inverse(cHat);

        for (var i = 0; i < ring.n; i++) {
          expect(c.coeffs[i], school.coeffs[i], reason: '$label coeff $i');
        }
      });

      test('$label boundary polys agree with schoolbook', () {
        final ntt = NttEngine(ring);
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
          final school = RingMul.schoolbookNegacyclic(a, b, ring);
          final cHat = Basemul.pointwise(ntt.forward(a), ntt.forward(b), ring);
          final c = ntt.inverse(cHat);
          for (var i = 0; i < n; i++) {
            expect(
              c.coeffs[i],
              school.coeffs[i],
              reason: '$label boundary coeff $i',
            );
          }
        }
      });
    }
  });

  group('Montgomery q=12289', () {
    final mp = MontgomeryParams.fnDsa;

    test('params ready and constants', () {
      expect(mp.isReady, isTrue);
      expect(mp.q, 12289);
      expect(mp.logR, 16);
      expect(mp.nPrime, 12287);
      expect(mp.r2, 10952);
    });

    test('toMont / fromMont roundtrip', () {
      for (final a in [0, 1, 12288, 1000, 7777]) {
        final m = ModQ.toMont(a, mp);
        final back = ModQ.fromMont(m, mp);
        expect(back, a % 12289);
      }
    });

    test('montMul in domain', () {
      final a = 1234;
      final b = 5678;
      final am = ModQ.toMont(a, mp);
      final bm = ModQ.toMont(b, mp);
      final cm = ModQ.montMul(am, bm, mp);
      final c = ModQ.fromMont(cm, mp);
      expect(c, (a * b) % 12289);
    });
  });
}

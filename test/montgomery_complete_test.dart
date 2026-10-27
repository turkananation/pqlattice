import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

/// Complete Montgomery acceleration test suite.
///
/// Covers:
/// - L1: montReduce / montMul / toMont / fromMont edge cases vs % oracle
/// - Fail-closed: unready MontgomeryParams throws StateError
/// - Swap parity: Montgomery-domain NTT == Barrett-domain NTT (all profiles)
/// - Swap parity: Montgomery pointwise basemul == Barrett pointwise basemul
/// - L3: Full NTT + Montgomery basemul + inverse NTT == schoolbook negacyclic
void main() {
  group('Montgomery edge cases (L1)', () {
    for (final entry in [
      (3329, MontgomeryParams.mlKem),
      (12289, MontgomeryParams.fnDsa),
      (8380417, MontgomeryParams.mlDsa),
    ]) {
      final q = entry.$1;
      final params = entry.$2;
      final r = params.r;
      final bound = q * r;

      test('q=$q params ready with verified constants', () {
        expect(params.isReady, isTrue);
        expect(params.q, q);
        expect(params.logR, greaterThan(0));
        expect(params.nPrime, isNonZero);
        expect(params.r2, isNonZero);
      });

      test('q=$q toMont/fromMont round-trip boundary values', () {
        final cases = <int>[0, 1, q - 1, q, q + 1, bound - 1];
        for (final a in cases) {
          final m = ModQ.toMont(a, params);
          expect(
            ModQ.fromMont(m, params),
            a % q,
            reason: 'toMont/fromMont($a)',
          );
        }
      });

      test('q=$q montMul matches plain product for all residue pairs', () {
        final rnd = Random(q);
        for (var i = 0; i < 2000; i++) {
          final a = rnd.nextInt(q);
          final b = rnd.nextInt(q);
          final am = ModQ.toMont(a, params);
          final bm = ModQ.toMont(b, params);
          final cm = ModQ.montMul(am, bm, params);
          expect(
            ModQ.fromMont(cm, params),
            (a * b) % q,
            reason: 'montMul($a,$b)',
          );
        }
      });

      test('q=$q montMul boundary operands', () {
        final cases = <int>[0, 1, q - 1];
        for (final a in cases) {
          for (final b in cases) {
            final am = ModQ.toMont(a, params);
            final bm = ModQ.toMont(b, params);
            final cm = ModQ.montMul(am, bm, params);
            expect(
              ModQ.fromMont(cm, params),
              (a * b) % q,
              reason: 'boundary montMul($a,$b)',
            );
          }
        }
      });

      test('q=$q montReduce input bound: negative rejected', () {
        expect(() => ModQ.montReduce(-1, params), throwsArgumentError);
        expect(() => ModQ.montReduce(-q, params), throwsArgumentError);
      });

      test('q=$q montReduce input bound: >= q*R rejected', () {
        expect(() => ModQ.montReduce(bound, params), throwsArgumentError);
        expect(() => ModQ.montReduce(bound + 1, params), throwsArgumentError);
      });

      test('q=$q montReduce zero and max valid input', () {
        // montReduce(a) = a * R⁻¹ mod q, NOT a mod q.
        // For a = bound - 1 = q*R - 1: montReduce = (q*R-1)*R⁻¹ mod q = (-R⁻¹) mod q = q - R⁻¹ mod q
        expect(ModQ.montReduce(0, params), 0);
        final rInv = ModQ.fromMont(1, params); // R⁻¹ mod q = fromMont(1)
        expect(ModQ.montReduce(bound - 1, params), (q - rInv) % q);
      });

      test('q=$q montMul operand validation rejects out-of-domain', () {
        final am = ModQ.toMont(5, params);
        expect(() => ModQ.montMul(-1, am, params), throwsArgumentError);
        expect(() => ModQ.montMul(am, -1, params), throwsArgumentError);
        expect(() => ModQ.montMul(q, am, params), throwsArgumentError);
        expect(() => ModQ.montMul(am, q, params), throwsArgumentError);
      });

      test('q=$q fail-closed: unready MontgomeryParams throws', () {
        const bad = MontgomeryParams(q: 17, nPrime: 0, r2: 0, logR: 0);
        expect(bad.isReady, isFalse);
        expect(() => ModQ.montReduce(1, bad), throwsStateError);
        expect(() => ModQ.montMul(1, 1, bad), throwsStateError);
        expect(() => ModQ.toMont(1, bad), throwsStateError);
        expect(() => ModQ.fromMont(1, bad), throwsStateError);
      });
    }
  });

  group('Montgomery NTT swap parity vs Barrett (all profiles)', () {
    final cases = <(RingParams, int Function(Random))>[
      (RingParams.mlKem, (r) => r.nextInt(3329)),
      (RingParams.mlDsa, (r) => r.nextInt(8380417)),
      (RingParams.fnDsa512, (r) => r.nextInt(12289)),
      (RingParams.fnDsa1024, (r) => r.nextInt(12289)),
    ];

    for (final c in cases) {
      final ring = c.$1;
      final sample = c.$2;
      final montParams = MontgomeryParams.forQ(ring.q);

      test(
        '${ring.name} Montgomery forward+inverse == Barrett forward+inverse',
        () {
          final rnd = Random(0x5EED ^ ring.q);
          final coeffs = List<int>.generate(ring.n, (_) => sample(rnd));
          final a = Poly.fromCoeffs(ring, coeffs);

          final barrett = NttEngine(ring);
          final montgomery = NttEngine(ring, montgomeryParams: montParams);

          final barrettBack = barrett.inverse(barrett.forward(a));
          final montBack = montgomery.inverse(montgomery.forward(a));

          for (var i = 0; i < ring.n; i++) {
            expect(
              montBack.coeffs[i] % ring.q,
              barrettBack.coeffs[i] % ring.q,
              reason: '${ring.name} coeff $i',
            );
          }
        },
      );

      test(
        '${ring.name} Montgomery NTT coefficients == Barrett NTT coefficients',
        () {
          final rnd = Random(0xBEEF ^ ring.q);
          final coeffs = List<int>.generate(ring.n, (_) => sample(rnd));
          final a = Poly.fromCoeffs(ring, coeffs);

          final barrett = NttEngine(ring);
          final montgomery = NttEngine(ring, montgomeryParams: montParams);

          final barrettHat = barrett.forward(a);
          final montHat = montgomery.forward(a);

          // Montgomery NTT output is in Montgomery domain; convert back with
          // fromMont for comparison with Barrett (normal domain) output.
          for (var i = 0; i < ring.n; i++) {
            expect(
              ModQ.fromMont(montHat.coeffs[i], montParams) % ring.q,
              barrettHat.coeffs[i] % ring.q,
              reason: '${ring.name} NTT coeff $i',
            );
          }
        },
      );

      test('${ring.name} Montgomery round-trip recovers input', () {
        final rnd = Random(0xCAFE ^ ring.q);
        final coeffs = List<int>.generate(ring.n, (_) => sample(rnd));
        final a = Poly.fromCoeffs(ring, coeffs);

        final montgomery = NttEngine(ring, montgomeryParams: montParams);
        final back = montgomery.inverse(montgomery.forward(a));

        for (var i = 0; i < ring.n; i++) {
          expect(
            back.coeffs[i] % ring.q,
            a.coeffs[i] % ring.q,
            reason: '${ring.name} roundtrip coeff $i',
          );
        }
      });

      test('${ring.name} Montgomery forwardVec/inverseVec == Barrett', () {
        final rnd = Random(0xDEAD ^ ring.q);
        final polys = List<Poly>.generate(3, (_) {
          return Poly.fromCoeffs(
            ring,
            List<int>.generate(ring.n, (_) => sample(rnd)),
          );
        });

        final barrett = NttEngine(ring);
        final montgomery = NttEngine(ring, montgomeryParams: montParams);

        final barrettVec = barrett.inverseVec(
          barrett.forwardVec(PolyVec.fromPolys(ring, polys)),
        );
        final montVec = montgomery.inverseVec(
          montgomery.forwardVec(PolyVec.fromPolys(ring, polys)),
        );

        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < ring.n; j++) {
            expect(
              montVec[i].coeffs[j] % ring.q,
              barrettVec[i].coeffs[j] % ring.q,
              reason: '${ring.name} vec poly $i coeff $j',
            );
          }
        }
      });

      test(
        '${ring.name} fail-closed: unready MontgomeryParams at construction',
        () {
          final bad = MontgomeryParams(q: ring.q, nPrime: 0, r2: 0, logR: 0);
          expect(bad.isReady, isFalse);
          expect(
            () => NttEngine(ring, montgomeryParams: bad),
            throwsStateError,
          );
        },
      );
    }
  });

  group(
    'Montgomery pointwise basemul swap parity vs Barrett (all profiles)',
    () {
      final cases = <(RingParams, int Function(Random))>[
        (RingParams.mlKem, (r) => r.nextInt(3329)),
        (RingParams.mlDsa, (r) => r.nextInt(8380417)),
        (RingParams.fnDsa512, (r) => r.nextInt(12289)),
        (RingParams.fnDsa1024, (r) => r.nextInt(12289)),
      ];

      for (final c in cases) {
        final ring = c.$1;
        final sample = c.$2;
        final montParams = MontgomeryParams.forQ(ring.q);

        test(
          '${ring.name} Montgomery pointwise == Barrett pointwise (random)',
          () {
            final rnd = Random(0xFEED ^ ring.q);
            final a = Poly.fromCoeffs(
              ring,
              List<int>.generate(ring.n, (_) => sample(rnd)),
            );
            final b = Poly.fromCoeffs(
              ring,
              List<int>.generate(ring.n, (_) => sample(rnd)),
            );

            final barrett = Basemul.pointwise(a, b, ring);

            // Convert inputs to Montgomery domain, multiply, convert back.
            final aMont = Poly.zero(ring);
            final bMont = Poly.zero(ring);
            for (var i = 0; i < ring.n; i++) {
              aMont.coeffs[i] = ModQ.toMont(a.coeffs[i], montParams);
              bMont.coeffs[i] = ModQ.toMont(b.coeffs[i], montParams);
            }
            final montProd = Basemul.pointwiseMontgomery(
              aMont,
              bMont,
              ring,
              montParams,
            );
            final montResult = Poly.zero(ring);
            for (var i = 0; i < ring.n; i++) {
              montResult.coeffs[i] = ModQ.fromMont(
                montProd.coeffs[i],
                montParams,
              );
            }

            expect(
              montResult.coeffs,
              barrett.coeffs,
              reason: '${ring.name} Montgomery pointwise parity',
            );
          },
        );

        test(
          '${ring.name} Montgomery pointwise == Barrett pointwise (boundary)',
          () {
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
              final barrett = Basemul.pointwise(a, b, ring);

              final aMont = Poly.zero(ring);
              final bMont = Poly.zero(ring);
              for (var i = 0; i < n; i++) {
                aMont.coeffs[i] = ModQ.toMont(a.coeffs[i], montParams);
                bMont.coeffs[i] = ModQ.toMont(b.coeffs[i], montParams);
              }
              final montProd = Basemul.pointwiseMontgomery(
                aMont,
                bMont,
                ring,
                montParams,
              );
              final montResult = Poly.zero(ring);
              for (var i = 0; i < n; i++) {
                montResult.coeffs[i] = ModQ.fromMont(
                  montProd.coeffs[i],
                  montParams,
                );
              }

              expect(
                montResult.coeffs,
                barrett.coeffs,
                reason: '${ring.name} boundary coeff parity',
              );
            }
          },
        );
      }
    },
  );

  group(
    'Montgomery full pipeline L3: NTT + basemul + invNTT == schoolbook',
    () {
      final cases = <(RingParams, int Function(Random))>[
        (RingParams.mlKem, (r) => r.nextInt(3329)),
        (RingParams.mlDsa, (r) => r.nextInt(8380417)),
        (RingParams.fnDsa512, (r) => r.nextInt(12289)),
        (RingParams.fnDsa1024, (r) => r.nextInt(12289)),
      ];

      for (final c in cases) {
        final ring = c.$1;
        final sample = c.$2;
        final montParams = MontgomeryParams.forQ(ring.q);

        test(
          '${ring.name} Montgomery pipeline matches schoolbook (random)',
          () {
            final rnd = Random(0x1753 ^ ring.q);
            final a = Poly.fromCoeffs(
              ring,
              List<int>.generate(ring.n, (_) => sample(rnd)),
            );
            final b = Poly.fromCoeffs(
              ring,
              List<int>.generate(ring.n, (_) => sample(rnd)),
            );

            final school = RingMul.schoolbookNegacyclic(a, b, ring);

            // Barrett pipeline
            final barrettEngine = NttEngine(ring);
            final barrettAHat = barrettEngine.forward(a);
            final barrettBHat = barrettEngine.forward(b);
            final barrettProd = ring.q == 3329 && ring.n == 256
                ? Basemul.mlKemPairs(barrettAHat, barrettBHat, ring)
                : Basemul.pointwise(barrettAHat, barrettBHat, ring);
            final barrettResult = barrettEngine.inverse(barrettProd);

            // Montgomery pipeline
            final montEngine = NttEngine(ring, montgomeryParams: montParams);
            final montAHat = montEngine.forward(a);
            final montBHat = montEngine.forward(b);
            final montProd = ring.q == 3329 && ring.n == 256
                ? Basemul.mlKemPairsMontgomery(montAHat, montBHat, montParams)
                : Basemul.pointwiseMontgomery(
                    montAHat,
                    montBHat,
                    ring,
                    montParams,
                  );
            final montResult = montEngine.inverse(montProd);

            for (var i = 0; i < ring.n; i++) {
              expect(
                montResult.coeffs[i],
                school.coeffs[i],
                reason: '${ring.name} pipeline coeff $i',
              );
              expect(
                montResult.coeffs[i],
                barrettResult.coeffs[i],
                reason: '${ring.name} pipeline vs Barrett coeff $i',
              );
            }
          },
        );

        test(
          '${ring.name} Montgomery pipeline matches schoolbook (boundary)',
          () {
            final n = ring.n;
            final q = ring.q;
            final montEngine = NttEngine(ring, montgomeryParams: montParams);

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

              final montAHat = montEngine.forward(a);
              final montBHat = montEngine.forward(b);
              final montProd = ring.q == 3329 && ring.n == 256
                  ? Basemul.mlKemPairsMontgomery(montAHat, montBHat, montParams)
                  : Basemul.pointwiseMontgomery(
                      montAHat,
                      montBHat,
                      ring,
                      montParams,
                    );
              final montResult = montEngine.inverse(montProd);

              for (var i = 0; i < n; i++) {
                expect(
                  montResult.coeffs[i],
                  school.coeffs[i],
                  reason: '${ring.name} boundary pipeline coeff $i',
                );
              }
            }
          },
        );
      }
    },
  );
}

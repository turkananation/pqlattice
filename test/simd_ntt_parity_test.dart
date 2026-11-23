import 'dart:math';
import 'dart:typed_data';

import 'package:pqlattice/pqlattice.dart';
import 'package:pqlattice/src/ntt/ntt_scalar.dart';
import 'package:pqlattice/src/simd/ntt_simd_int32x4.dart';
import 'package:pqlattice/src/simd/ntt_workspace.dart';
import 'package:test/test.dart';

/// Bit-exactness gates for the staged `Int32x4` NTT kernels.
///
/// Three layers:
///
/// 1. **Kernel parity** — `NttSimdInt32x4` vs `NttScalar` on identical staged
///    input, coefficient-wise, including FN-DSA-512 inverse (which is gated
///    off in `accelerated` mode but must still be correct).
/// 2. **Adversarial inputs** — zeros, ones, `q-1`, and alternating extremes, to
///    pin the branchless canonicalization at both range endpoints.
/// 3. **Engine parity** — `reference` / `optimizedScalar` / `accelerated` /
///    `simd` all agree on random polynomials, and `inverse(forward(x)) == x`.
void main() {
  final profiles = <(RingParams, int)>[
    (RingParams.mlKem, 3329),
    (RingParams.mlDsa, 8380417),
    (RingParams.fnDsa512, 12289),
    (RingParams.fnDsa1024, 12289),
  ];

  for (final (ring, q) in profiles) {
    final n = ring.n;
    final params = NttParams.forRing(ring);

    // ML-DSA accelerated kernels take Montgomery-form twiddles.
    final zetas = ring.q == 8380417
        ? params.zetas
              .map((z) => ModQ.toMont(z, MontgomeryParams.mlDsa))
              .toList(growable: false)
        : params.zetas;
    final invScale = ring.q == 8380417
        ? ModQ.toMont(params.invNScale, MontgomeryParams.mlDsa)
        : params.invNScale;

    Int32List scalarForward(List<int> values) {
      final f = Int32List.fromList(values);
      switch (ring.name) {
        case 'ml-kem':
          NttScalar.mlKemForward(f, zetas);
        case 'ml-dsa':
          NttScalar.mlDsaForward(f, zetas);
        default:
          NttScalar.fnDsaForward(f, n, zetas);
      }
      return f;
    }

    Int32List vectorForward(List<int> values) {
      final ws = NttWorkspace(n)..lanes.setAll(0, values);
      switch (ring.name) {
        case 'ml-kem':
          NttSimdInt32x4.mlKemForward(ws, zetas);
        case 'ml-dsa':
          NttSimdInt32x4.mlDsaForward(ws, zetas);
        default:
          NttSimdInt32x4.fnDsaForward(ws, n, zetas);
      }
      return ws.lanes;
    }

    Int32List scalarInverse(List<int> values) {
      final f = Int32List.fromList(values);
      switch (ring.name) {
        case 'ml-kem':
          NttScalar.mlKemInverse(f, zetas, invScale);
        case 'ml-dsa':
          NttScalar.mlDsaInverse(f, zetas, invScale);
        default:
          NttScalar.fnDsaInverse(f, n, zetas, invScale);
      }
      return f;
    }

    Int32List vectorInverse(List<int> values) {
      final ws = NttWorkspace(n)..lanes.setAll(0, values);
      switch (ring.name) {
        case 'ml-kem':
          NttSimdInt32x4.mlKemInverse(ws, zetas, invScale);
        case 'ml-dsa':
          NttSimdInt32x4.mlDsaInverse(ws, zetas, invScale);
        default:
          NttSimdInt32x4.fnDsaInverse(ws, n, zetas, invScale);
      }
      return ws.lanes;
    }

    List<int> randomPoly(Random rnd) =>
        List<int>.generate(n, (_) => rnd.nextInt(q));

    group('${ring.name} split-pass SIMD parity', () {
      test('forward: 25 random polys are bit-identical to typed scalar', () {
        final rnd = Random(0xA11CE ^ ring.q ^ n);
        for (var trial = 0; trial < 25; trial++) {
          final values = randomPoly(rnd);
          expect(
            vectorForward(values),
            scalarForward(values),
            reason: '${ring.name} forward trial $trial',
          );
        }
      });

      test('inverse: 25 random polys are bit-identical to typed scalar', () {
        final rnd = Random(0xB0B ^ ring.q ^ n);
        for (var trial = 0; trial < 25; trial++) {
          final values = randomPoly(rnd);
          expect(
            vectorInverse(values),
            scalarInverse(values),
            reason: '${ring.name} inverse trial $trial',
          );
        }
      });

      test('adversarial inputs: both range endpoints agree', () {
        final patterns = <String, List<int>>{
          'zeros': List<int>.filled(n, 0),
          'ones': List<int>.filled(n, 1),
          'q-1': List<int>.filled(n, q - 1),
          'alternating 0 / q-1': List<int>.generate(
            n,
            (i) => i.isEven ? 0 : q - 1,
          ),
          'ramp': List<int>.generate(n, (i) => i % q),
          'q-1 minus ramp': List<int>.generate(n, (i) => (q - 1 - i) % q),
          'half q': List<int>.filled(n, q >> 1),
        };
        for (final entry in patterns.entries) {
          expect(
            vectorForward(entry.value),
            scalarForward(entry.value),
            reason: '${ring.name} forward pattern ${entry.key}',
          );
          expect(
            vectorInverse(entry.value),
            scalarInverse(entry.value),
            reason: '${ring.name} inverse pattern ${entry.key}',
          );
        }
      });
    });

    group('${ring.name} engine mode parity', () {
      test('reference / scalar / accelerated / simd agree and round-trip', () {
        final rnd = Random(0xC0FFEE ^ ring.q ^ n);
        final engines = <KernelMode, NttEngine>{
          for (final mode in <KernelMode>[
            KernelMode.reference,
            KernelMode.optimizedScalar,
            KernelMode.accelerated,
            KernelMode.simd,
          ])
            mode: NttEngine(ring, mode: mode),
        };
        for (var trial = 0; trial < 5; trial++) {
          final values = randomPoly(rnd);
          final base = Poly.fromCoeffs(ring, values);
          final reference = engines[KernelMode.reference]!.forward(base);
          for (final entry in engines.entries) {
            final out = entry.value.forward(base);
            expect(
              out.coeffs,
              reference.coeffs,
              reason: '${ring.name} ${entry.key.name} forward trial $trial',
            );
            // Input must not be mutated by the allocating API.
            expect(base.coeffs, values, reason: '${entry.key.name} mutated input');
            final back = entry.value.inverse(out);
            expect(
              back.coeffs,
              values,
              reason: '${ring.name} ${entry.key.name} round-trip trial $trial',
            );
          }
        }
      });

      test('in-place API matches the allocating API', () {
        final rnd = Random(0x5EED ^ ring.q ^ n);
        final engine = NttEngine(ring, mode: KernelMode.accelerated);
        for (var trial = 0; trial < 5; trial++) {
          final values = randomPoly(rnd);
          final p = Poly.fromCoeffs(ring, values);
          final allocated = engine.forward(p).coeffs;
          engine.forwardInPlace(p);
          expect(p.coeffs, allocated, reason: 'forwardInPlace trial $trial');

          final q1 = Poly.fromCoeffs(ring, values);
          final invAllocated = engine.inverse(q1).coeffs;
          engine.inverseInPlace(q1);
          expect(q1.coeffs, invAllocated, reason: 'inverseInPlace trial $trial');
        }
      });
    });
  }
}
import 'package:pqlattice/pqlattice.dart';
import 'package:pqlattice/src/simd/simd_capability.dart';
import 'package:test/test.dart';

void main() {
  group('LatticeKernels', () {
    test('default mode is accelerated', () {
      expect(LatticeKernels.defaultMode, KernelMode.accelerated);
    });

    test('reference and optimizedScalar never prefer SIMD', () {
      expect(LatticeKernels.preferSimd(KernelMode.reference), isFalse);
      expect(LatticeKernels.preferSimd(KernelMode.optimizedScalar), isFalse);
      expect(LatticeKernels.preferSimd(KernelMode.scalar), isFalse);
    });

    test('backend gate is enabled on the VM and never on dart2js', () {
      // The test suite runs on the Dart VM, where Int32x4 lowers to real
      // vector registers.
      expect(SimdCapability.isDart2js, isFalse);
      expect(LatticeKernels.simdEnabled, isTrue);
      expect(LatticeKernels.preferSimd(KernelMode.accelerated), isTrue);
      expect(LatticeKernels.preferSimd(KernelMode.auto), isTrue);
      expect(LatticeKernels.preferSimd(KernelMode.simd), isTrue);
    });

    test('per-profile evidence gate matches doc/SIMD.md §4', () {
      // All four shipped profiles clear the 1.5x engine-level bar: ML-KEM
      // 2.05x-2.31x, ML-DSA 1.87x-2.12x, FN-DSA 1.51x-1.58x.
      for (final ring in <RingParams>[
        RingParams.mlKem,
        RingParams.mlDsa,
        RingParams.fnDsa512,
        RingParams.fnDsa1024,
      ]) {
        for (final inverse in <bool>[false, true]) {
          expect(
            LatticeKernels.preferSimdNtt(
              KernelMode.accelerated,
              ring,
              inverse: inverse,
            ),
            isTrue,
            reason: '${ring.name} inverse=$inverse',
          );
        }
      }
    });

    test('scalar and reference modes never take the vector kernel', () {
      for (final mode in <KernelMode>[
        KernelMode.reference,
        KernelMode.optimizedScalar,
        KernelMode.scalar,
      ]) {
        for (final inverse in <bool>[false, true]) {
          expect(
            LatticeKernels.preferSimdNtt(
              mode,
              RingParams.mlKem,
              inverse: inverse,
            ),
            isFalse,
          );
          expect(
            LatticeKernels.preferSimdNtt(
              mode,
              RingParams.fnDsa512,
              inverse: inverse,
            ),
            isFalse,
          );
        }
      }
    });

    test('KernelMode.simd forces the vector kernel, accelerated gates it', () {
      // FN-DSA is the lower-margin profile; simd must still force it.
      expect(
        LatticeKernels.preferSimdNtt(
          KernelMode.simd,
          RingParams.fnDsa512,
          inverse: true,
        ),
        isTrue,
      );
      // A toy ring is never in the evidence table, but simd still runs it.
      const toy = RingParams(q: 17, n: 16, name: 'toy');
      expect(
        LatticeKernels.preferSimdNtt(
          KernelMode.simd,
          toy,
          inverse: false,
        ),
        isTrue,
      );
      expect(
        LatticeKernels.preferSimdNtt(
          KernelMode.accelerated,
          toy,
          inverse: false,
        ),
        isFalse,
      );
    });

    test('useReference only for reference mode', () {
      expect(LatticeKernels.useReference(KernelMode.reference), isTrue);
      expect(LatticeKernels.useReference(KernelMode.accelerated), isFalse);
    });
  });
}
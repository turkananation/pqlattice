import 'package:pqlattice/pqlattice.dart';
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

    test('accelerated respects SimdCapability flag', () {
      // Scaffold keeps SimdCapability.isLikelyBeneficial == false.
      expect(LatticeKernels.preferSimd(KernelMode.accelerated), isFalse);
      expect(LatticeKernels.preferSimd(KernelMode.auto), isFalse);
    });

    test('useReference only for reference mode', () {
      expect(LatticeKernels.useReference(KernelMode.reference), isTrue);
      expect(LatticeKernels.useReference(KernelMode.accelerated), isFalse);
    });
  });
}

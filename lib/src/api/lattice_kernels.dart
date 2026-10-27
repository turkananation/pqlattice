import '../simd/simd_capability.dart';
import 'kernel_mode.dart';

/// Package-wide kernel policy.
///
/// Acceleration is **on by default**. See `doc/ACCELERATION.md`.
final class LatticeKernels {
  LatticeKernels._();

  /// Default mode for engines and facades: accelerated.
  static const KernelMode defaultMode = KernelMode.accelerated;

  /// Whether SIMD may be selected under [KernelMode.accelerated] / [KernelMode.simd].
  ///
  /// Starts conservative until AOT parity is recorded; when true, accelerated
  /// mode prefers SIMD. Optimized scalar remains accelerated (Barrett/NTT).
  static bool get simdEnabled => SimdCapability.isLikelyBeneficial;

  /// Prefer SIMD when mode allows and [simdEnabled] is true.
  static bool preferSimd(KernelMode mode) {
    final m = resolveKernelMode(mode);
    if (m == KernelMode.reference || m == KernelMode.optimizedScalar) {
      return false;
    }
    if (m == KernelMode.simd) return true;
    // accelerated
    return simdEnabled;
  }

  /// Whether to use reference (`%` / simple) algorithms.
  static bool useReference(KernelMode mode) =>
      resolveKernelMode(mode) == KernelMode.reference;
}

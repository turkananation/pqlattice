import '../ring/ring_params.dart';
import '../simd/simd_capability.dart';
import 'kernel_mode.dart';

/// Package-wide kernel policy.
///
/// Acceleration is **on by default**. See `doc/ACCELERATION.md`.
final class LatticeKernels {
  LatticeKernels._();

  /// Default mode for engines and facades: accelerated.
  static const KernelMode defaultMode = KernelMode.accelerated;

  /// Whether this backend can run `Int32x4` kernels at all.
  ///
  /// This is a backend fact, not a per-kernel decision: dart2js is excluded
  /// because its emulated `Int32x4` measured 2.7× slower than typed scalar.
  /// Use [preferSimdNtt] for the per-ring/per-direction evidence gate.
  static bool get simdEnabled => SimdCapability.supportsInt32x4;

  /// Prefer SIMD when the mode allows and the backend supports `Int32x4`.
  ///
  /// Backend-level only. Kernel dispatch must use [preferSimdNtt], which also
  /// applies the per-profile AOT evidence gate.
  static bool preferSimd(KernelMode mode) {
    final m = resolveKernelMode(mode);
    if (m == KernelMode.reference || m == KernelMode.optimizedScalar) {
      return false;
    }
    if (m == KernelMode.simd) return true;
    // accelerated
    return simdEnabled;
  }

  /// Whether the split-pass `Int32x4` NTT kernel should run for this ring.
  ///
  /// [inverse] selects the inverse transform. The gate is a measured AOT
  /// adoption threshold of **1.5× vs the scalar path on the same host**, taken
  /// at engine level (the callable `forwardInPlace` / `inverseInPlace` with
  /// staging included), because that is what callers run. Results are recorded
  /// in `doc/SIMD.md` §4. `KernelMode.simd` forces the kernel everywhere (it is
  /// residue-identical); `reference` and `optimizedScalar` never use it.
  ///
  /// Measured margin at engine level (Dart 3.14.0 x64 AOT):
  /// ML-KEM 2.05×–2.31×, ML-DSA 1.87×–2.12×, FN-DSA-512 1.51×–1.52×,
  /// FN-DSA-1024 1.57×–1.58×. All four profiles ship SIMD.
  static bool preferSimdNtt(
    KernelMode mode,
    RingParams ring, {
    required bool inverse,
  }) {
    final m = resolveKernelMode(mode);
    if (m == KernelMode.reference || m == KernelMode.optimizedScalar) {
      return false;
    }
    if (!SimdCapability.supportsInt32x4) return false;
    if (m == KernelMode.simd) return true;
    return simdNttEvidence(ring, inverse: inverse);
  }

  /// Per-profile AOT evidence table for the split-pass NTT kernel.
  ///
  /// `true` means the measured engine-level gain over the scalar path cleared
  /// the 1.5× adoption threshold on Dart 3.14.0 x64 AOT. Changing an entry
  /// requires re-measuring and updating `doc/SIMD.md` §4.
  static bool simdNttEvidence(RingParams ring, {required bool inverse}) {
    final q = ring.q;
    final n = ring.n;
    if (q == 3329 && n == 256) return true; // ML-KEM: 2.31× fwd / 2.05× inv
    if (q == 8380417 && n == 256) return true; // ML-DSA: 2.12× / 1.87×
    if (q == 12289 && (n == 512 || n == 1024))
      return true; // FN-DSA: 1.51×–1.58×
    return false;
  }

  /// Whether to use reference (`%` / simple) algorithms.
  static bool useReference(KernelMode mode) =>
      resolveKernelMode(mode) == KernelMode.reference;
}

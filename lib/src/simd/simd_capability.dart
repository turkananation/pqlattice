/// Whether SIMD kernels may be selected under the **accelerated** default.
///
/// Acceleration is always the goal ([doc/ACCELERATION.md](../../doc/ACCELERATION.md)).
/// SIMD is one accelerator among others (Barrett, structured NTT, layout).
///
/// Default is false until a measured, parity-tested SIMD path exists for the
/// target class of builds. Optimized scalar remains the accelerated fallback.
final class SimdCapability {
  SimdCapability._();

  /// When true, [KernelMode.accelerated] may dispatch SIMD kernels.
  static bool isLikelyBeneficial = false;
}

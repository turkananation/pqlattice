/// Selects which implementation class runs for NTT / basemul / heavy loops.
///
/// **Default is accelerated.** This package exists to make lattice math fast;
/// reference kernels are for oracles and debug, not the design-center path.
enum KernelMode {
  /// Best available accelerated path: SIMD when capable and parity-proven,
  /// otherwise optimized scalar (Barrett, structured NTT, etc.).
  ///
  /// This is the **default** for [NttEngine] and public facades.
  accelerated,

  /// Force hand-written SIMD kernels when available; if not, behave like
  /// optimized scalar (still accelerated relative to naive code).
  simd,

  /// Optimized scalar only (Barrett, no SIMD). Still production-grade speed
  /// path on backends without useful SIMD.
  optimizedScalar,

  /// Reference / oracle path (`%`, simple loops). For tests and debugging.
  reference,

  /// @Deprecated — alias of [accelerated]
  auto,

  /// @Deprecated — alias of [optimizedScalar] (not the educational slow path)
  scalar,
}

/// Resolves deprecated aliases to the canonical mode.
KernelMode resolveKernelMode(KernelMode mode) {
  switch (mode) {
    case KernelMode.auto:
      return KernelMode.accelerated;
    case KernelMode.scalar:
      return KernelMode.optimizedScalar;
    default:
      return mode;
  }
}

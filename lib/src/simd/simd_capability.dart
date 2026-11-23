/// Backend and evidence gate for the `Int32x4` NTT kernels.
///
/// Acceleration is always the goal ([doc/ACCELERATION.md](../../doc/ACCELERATION.md)).
/// SIMD is one accelerator among others (Barrett, structured NTT, packed
/// layout). Unlike the scalar accelerators, SIMD is only worth selecting on
/// backends where [Int32x4] lowers to a real vector register.
///
/// Backend behaviour of the split-pass kernel (Dart 3.14.0, x64; see
/// `doc/SIMD.md` §4 for the full table):
///
/// | Backend | `Int32x4` lowering | Split kernel vs scalar |
/// | ------- | ------------------ | ---------------------- |
/// | Dart VM (x64 AOT) | real SIMD | 1.09×–1.85× depending on ring and direction |
/// | dart2wasm | `v128` | not measured (Node 20 lacks wasm-gc) |
/// | dart2js | emulated on JS numbers | **0.50×** (2× slower, measured) |
///
/// So dart2js is disabled unconditionally, the VM is enabled, and Wasm is
/// enabled with no speed claim attached.
final class SimdCapability {
  SimdCapability._();

  /// `-DPQLATTICE_SIMD_OFF=true` disables SIMD on every backend.
  ///
  /// Highest priority: it also overrides [force].
  static const bool _off = bool.fromEnvironment('PQLATTICE_SIMD_OFF');

  /// `-DPQLATTICE_SIMD_FORCE=true` enables SIMD on backends this gate would
  /// otherwise leave on its measured default.
  static const bool _force = bool.fromEnvironment('PQLATTICE_SIMD_FORCE');

  /// True only when compiled by dart2js.
  ///
  /// `identical(0, 0.0)` is `true` on dart2js because `int` and `double` are
  /// both JavaScript numbers there. It is `false` on the Dart VM and on
  /// dart2wasm, where the two numeric types are distinct. This is the only
  /// reliable dart2js discriminator available: `bool.fromEnvironment` for
  /// `dart.library.io` is `false` on **both** dart2js and dart2wasm, so it
  /// cannot separate them. Evaluated once per isolate.
  static final bool _isDart2js = identical(0, 0.0);

  /// Whether `Int32x4` kernels may run on this backend.
  ///
  /// Does not mean "use SIMD for this kernel" — per-ring evidence lives in
  /// [LatticeKernels.preferSimdNtt].
  static bool get supportsInt32x4 {
    if (_off) return false;
    if (_force) return true;
    return !_isDart2js;
  }

  /// Whether the current build is dart2js (exposed for diagnostics/tests).
  static bool get isDart2js => _isDart2js;
}
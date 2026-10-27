/// Parameters for a cyclotomic ring \(\mathbb{Z}_q[x]/(x^n + 1)\).
///
/// Jurisdictional boundary: sizes and modulus only — no NTT/FFT execution.
///
/// Supported named presets (math targets for scheme packages):
/// - [mlKem] — FIPS 203 ring
/// - [mlDsa] — FIPS 204 ring (tables later)
/// - [fnDsa512] / [fnDsa1024] — FN-DSA / Falcon (FIPS 206) integer ring \(q=12289\)
final class RingParams {
  /// Prime modulus \(q\).
  final int q;

  /// Polynomial degree (\(n\) coefficients); power of two for NTT-friendly sets.
  final int n;

  /// Human-readable preset name.
  final String name;

  const RingParams({required this.q, required this.n, required this.name});

  /// FIPS 203 ML-KEM: \(q = 3329\), \(n = 256\).
  ///
  /// Does **not** claim a full ML-KEM implementation.
  static const RingParams mlKem = RingParams(q: 3329, n: 256, name: 'ml-kem');

  /// FIPS 204 ML-DSA: \(q = 8380417\), \(n = 256\).
  ///
  /// Integer NTT tables ship in this package for math-layer use by `pqcrypto`.
  static const RingParams mlDsa = RingParams(
    q: 8380417,
    n: 256,
    name: 'ml-dsa',
  );

  /// FN-DSA-512 / Falcon-512 integer ring: \(q = 12289\), \(n = 512\).
  ///
  /// Integer NTT over \(\mathbb{Z}_q[x]/(x^n+1)\) for verification and
  /// \(q\)-domain products. Does **not** include floating-point FFT sampling
  /// or the full FN-DSA signature scheme (see docs).
  static const RingParams fnDsa512 = RingParams(
    q: 12289,
    n: 512,
    name: 'fn-dsa-512',
  );

  /// FN-DSA-1024 / Falcon-1024 integer ring: \(q = 12289\), \(n = 1024\).
  static const RingParams fnDsa1024 = RingParams(
    q: 12289,
    n: 1024,
    name: 'fn-dsa-1024',
  );

  /// True if this ring matches FN-DSA integer modulus/degree family.
  bool get isFnDsaIntegerRing => q == 12289 && (n == 512 || n == 1024);

  @override
  String toString() => 'RingParams($name, q=$q, n=$n)';
}

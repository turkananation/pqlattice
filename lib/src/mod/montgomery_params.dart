/// Montgomery domain parameters for modular multiplication.
///
/// Uses radix \\(R = 2^{w}\\) with [nPrime] = \\(-q^{-1} \\bmod R\\) and
/// [r2] = \\(R^2 \\bmod q\\).
///
/// **Ready profiles:**
/// - \\(q = 12289\\) (FN-DSA), \\(R = 2^{16}\\) — Falcon-style word size
/// - \\(q = 3329\\) (ML-KEM), \\(R = 2^{16}\\)
///
/// ML-DSA (\\(q = 8380417\\)) may use \\(R = 2^{32}\\) when enabled.
final class MontgomeryParams {
  final int q;
  final int nPrime;
  final int r2;
  final int logR;

  const MontgomeryParams({
    required this.q,
    required this.nPrime,
    required this.r2,
    required this.logR,
  });

  int get rMask => (1 << logR) - 1;
  int get r => 1 << logR;

  bool get isReady => nPrime != 0 && r2 != 0 && logR > 0;

  factory MontgomeryParams.forQ(int q) {
    if (q == 12289) {
      // R=2^16; nPrime = -q^{-1} mod R = 12287; R^2 mod q = 10952
      return const MontgomeryParams(
        q: 12289,
        nPrime: 12287,
        r2: 10952,
        logR: 16,
      );
    }
    if (q == 3329) {
      // R = 2^16. nPrime = -q^{-1} mod R = 3327; R^2 mod q = 1353.
      return const MontgomeryParams(q: 3329, nPrime: 3327, r2: 1353, logR: 16);
    }
    if (q == 8380417) {
      // R = 2^32 for 23-bit modulus. nPrime = -q^{-1} mod R; R^2 mod q.
      // Verified by toMont/fromMont and montMul identities in tests.
      return const MontgomeryParams(
        q: 8380417,
        nPrime: 4236238847,
        r2: 2365951,
        logR: 32,
      );
    }
    return MontgomeryParams(q: q, nPrime: 0, r2: 0, logR: 0);
  }

  static final MontgomeryParams fnDsa = MontgomeryParams.forQ(12289);
  static final MontgomeryParams mlKem = MontgomeryParams.forQ(3329);
  static final MontgomeryParams mlDsa = MontgomeryParams.forQ(8380417);
}

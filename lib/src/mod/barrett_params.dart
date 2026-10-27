/// Precomputed constants for Barrett reduction modulo [q].
///
/// Given an integer \(a\) in a documented input range, Barrett reduction
/// approximates \(\lfloor a / q \rfloor\) using a multiply-and-shift with
/// [mu] and [shift], then corrects with a small number of conditional
/// subtractions so the result lies in \([0, q)\).
///
/// When [isReady] is true, these parameters are the **default accelerated**
/// field reduction path for hot loops (NTT, basemul, coefficient reduce).
/// When not ready, callers must use [ModQ.reduce] (`%`) instead.
///
/// Parameter selection is constrained by the interop rule: observable residues
/// must match the reference modular reduction used by `pqcrypto` paths that
/// lock to OpenSSL / BoringSSL / liboqs / AWS-LC. See `doc/REDUCTION.md`.
final class BarrettParams {
  /// Modulus \(q > 0\).
  final int q;

  /// Multiplier \(\mu = \lfloor 2^{\mathrm{shift}} / q \rfloor\).
  final int mu;

  /// Right-shift after the \(\mu\) product (Barrett \(k\)).
  final int shift;

  /// Documented maximum \(|a|\) (or unsigned magnitude) this recipe is
  /// tested against. Products larger than this may need an extra full
  /// reduction or a wider recipe.
  final int maxInputAbs;

  const BarrettParams({
    required this.q,
    required this.mu,
    required this.shift,
    this.maxInputAbs = 0,
  });

  /// Returns ready parameters for known lattice moduli, or an unready
  /// instance (`mu == 0`) for unknown \(q\).
  factory BarrettParams.forQ(int q) {
    // ML-KEM (FIPS 203): q = 3329.
    // μ = floor(2^24 / 3329) = 5039. Sufficient for products of two residues
    // and typical incomplete-NTT intermediate growth under tested bounds.
    if (q == 3329) {
      return const BarrettParams(
        q: 3329,
        mu: 5039,
        shift: 24,
        maxInputAbs: 3329 * 3329,
      );
    }
    // FN-DSA / Falcon integer ring: q = 12289.
    // μ = floor(2^24 / 12289) = 1365.
    if (q == 12289) {
      return const BarrettParams(
        q: 12289,
        mu: 1365,
        shift: 24,
        maxInputAbs: 12289 * 12289,
      );
    }
    // ML-DSA (FIPS 204): q = 8380417 (~23-bit).
    // shift = 32 is insufficient for a full product of two residues (~46-bit).
    // μ = floor(2^48 / 8380417) = 33587228 covers products in [0, q^2] and
    // modest headroom used in NTT layers. Verified against reference `%`.
    if (q == 8380417) {
      return const BarrettParams(
        q: 8380417,
        mu: 33587228,
        shift: 48,
        maxInputAbs: 8380417 * 8380417,
      );
    }
    return BarrettParams(q: q, mu: 0, shift: 0, maxInputAbs: 0);
  }

  /// Preset for ML-KEM (\(q = 3329\)).
  static final BarrettParams mlKem = BarrettParams.forQ(3329);

  /// Preset for FN-DSA integer modulus (\(q = 12289\)).
  static final BarrettParams fnDsa = BarrettParams.forQ(12289);

  /// Preset for ML-DSA (\(q = 8380417\)).
  static final BarrettParams mlDsa = BarrettParams.forQ(8380417);

  /// Whether [mu] and [shift] form a usable accelerated recipe.
  bool get isReady => mu != 0 && shift != 0;
}

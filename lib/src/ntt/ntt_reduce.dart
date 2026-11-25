/// Reduction recipes shared by the `List<int>`, typed scalar, and `Int32x4`
/// NTT kernels.
///
/// These are the **same** chains documented on [NttEngine]'s accelerated
/// kernels; they live here so a kernel rewrite cannot accidentally drift from
/// the certified residue function. Provenance and bounds are documented at the
/// call sites in `doc/REDUCTION.md`.
library;

/// Barrett reduction for ML-KEM products: q = 3329, v = 20159, shift = 26.
///
/// `20159 = ceil(2^26 / 3329)` — the pqcrypto-parity ceil-quotient form.
/// Input bound: `0 <= a, b < q`, so `raw = a * b < q^2 ≈ 1.1e7 < 2^24`.
/// Inside that bound the estimate lands in `[-70, q)`. One sign-mask
/// correction `r + (q & (r >> 63))` equals `raw % q`. There is no division.
/// Certified exhaustively by `test/mlkem_mul_barrett_exhaustive_test.dart`.
int mlKemMulBarrett(int a, int b) {
  const q = 3329;
  final raw = a * b;
  final r = raw - ((raw * 20159) >> 26) * q;
  return r + (q & (r >> 63));
}

/// Single-limb 32-bit-word Montgomery REDC for q = 8380417.
///
/// `m = ((prod mod 2^32) · nPrime) mod 2^32; u = (prod + m·q) >> 32`, one
/// conditional guard. Input bound `prod < 2^46` → `(prod + m·q) < 2^56`, so the
/// sum cannot wrap a 64-bit signed int. `nPrime = -q^{-1} mod 2^32`
/// (= 4236238847, shipped in [MontgomeryParams] for this ring).
int mlDsaRedc(int prod) {
  const q = 8380417;
  const mask = 0xFFFFFFFF;
  const nPrime = 4236238847;
  final m = ((prod & mask) * nPrime) & mask;
  final u = (prod + m * q) >> 32;
  return _csubq(u, q);
}

/// Montgomery product for `R = 2^16` (ML-KEM and FN-DSA).
///
/// [a] and [b] are Montgomery-domain residues in `[0, q)`. The result is
/// `a b R^{-1} mod q` in `[0, q)`, also in the Montgomery domain. One
/// conditional subtraction and a negative fix, both masks. Matches
/// [ModQ.montMul] on that bound, without the per-call range checks.
int montMulR16(int a, int b, int q, int nPrime) {
  const mask = 0xFFFF;
  final prod = a * b;
  final t = ((prod & mask) * nPrime) & mask;
  final u = (prod + t * q) >> 16;
  return _caddq(_csubq(u, q), q);
}

/// `r - q` when `r >= q`, otherwise `r`. [r] must be `< 2q`.
@pragma('vm:prefer-inline')
int maskCsub(int r, int q) => _csubq(r, q);

/// `r + q` when `r < 0`, otherwise `r`. [r] must be `> -q`.
@pragma('vm:prefer-inline')
int maskCadd(int r, int q) => _caddq(r, q);

/// `r - q` when `r >= q`, otherwise `r`. [r] must be `< 2q`.
int _csubq(int r, int q) {
  final sn = r - q;
  return r - (q & ~(sn >> 63));
}

/// `r + q` when `r < 0`, otherwise `r`.
int _caddq(int r, int q) => r + (q & (r >> 63));

/// Single-guard Barrett reduction for the FN-DSA product family:
/// q = 12289, shift = 27, mu = 10921 = floor(2^27 / 12289).
///
/// Documented input bound: `0 <= prod < q^2 = 151,019,521 < 2^28` (covers all
/// butterfly and final-scale products). The estimate is in `[0, 2q)`: exactly
/// one subtraction, never a second, never a negative fix, never a division.
/// Exhaustively certified over all 12289² products by
/// `test/fndsa_exhaustive_residue_test.dart`.
int fnDsaReduceK27(int prod) {
  const q = 12289;
  const mu = 10921;
  final r = prod - ((prod * mu) >> 27) * q;
  return _csubq(r, q);
}

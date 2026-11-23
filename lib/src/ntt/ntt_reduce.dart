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
/// `20159 = ceil(2^26 / 3329)` — the pqcrypto-parity single-guard form.
/// Input bound: `0 <= a, b < q`, so `raw = a * b < q^2 ≈ 1.1e7 < 2^24`.
/// Certified exhaustively over all 3329² products by
/// `test/barrett_mlkem_test.dart`; the `%` escape is defensive and unreachable
/// inside the bound.
int mlKemMulBarrett(int a, int b) {
  const q = 3329;
  final raw = a * b;
  final quot = (raw * 20159) >> 26;
  var r = raw - quot * q;
  if (r < 0 || r >= q) r %= q;
  return r;
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
  var u = (prod + m * q) >> 32;
  if (u >= q) u -= q;
  return u;
}

/// Single-guard Barrett reduction for the FN-DSA product family:
/// q = 12289, shift = 27, mu = 10921 = floor(2^27 / 12289).
///
/// Documented input bound: `0 <= prod < q^2 = 151,019,521 < 2^28` (covers all
/// butterfly and final-scale products). Two conditional subtractions, one
/// negative fix, and a defensive `%` escape that is unreachable for in-range
/// products (0 corrections observed under the bound). Exhaustively certified
/// over all 12289² products by `test/fndsa_exhaustive_residue_test.dart`.
int fnDsaReduceK27(int prod) {
  const q = 12289;
  const mu = 10921;
  final quot = (prod * mu) >> 27;
  var r = prod - quot * q;
  r = r >= q ? r - q : r;
  r = r >= q ? r - q : r;
  if (r < 0) r += q;
  if (r >= q) r %= q;
  return r;
}
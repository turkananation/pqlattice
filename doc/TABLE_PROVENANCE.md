# Table Provenance (Twiddles, invN, Gammas)

Last updated: 2026-10-27

Every NTT table shipped as **complete** must be traceable to a public
specification or a reference implementation that `pqcrypto` interop already
trusts.

Related: [TESTING.md](TESTING.md), [FN_DSA_MATH.md](FN_DSA_MATH.md),
[FIPS_ALIGNMENT.md](FIPS_ALIGNMENT.md), [PQCRYPTO_REUSE.md](PQCRYPTO_REUSE.md).

Code: `lib/src/ntt/mlkem_tables.dart`, `mldsa_tables.dart`, `fndsa_tables.dart`.

---

## 1. Rules

1. **No invented roots of unity.** Generate or port from cited sources only.
2. **Record source** in this file when marking a profile complete.
3. **Tests** must check length, `invN` consistency, and NTT roundtrip.
4. Prefer continuity with **`pqcrypto`** tables when Path B substitution is
   intended (same interop class as OpenSSL / liboqs paths).
5. Scaffold tables (empty or placeholder) must not pass “complete” status.

---

## 2. Register

### ML-KEM (\(q = 3329\), \(n = 256\), incomplete NTT)

| Item | Source / notes | Verification |
|------|----------------|--------------|
| `zetas` / bit-reversed twiddles | Port from `pqcrypto` `algos/kyber/poly.dart` `_zetas` (FIPS 203 / Go-style unsigned zetas). | Byte-identical to pqcrypto; length 128; `zetas[0] == 1`. |
| Gammas / paired basemul constants | Same family as ML-KEM basemul pairs; FIPS 203 Appendix A `ζ^{2·BitRev₇(i)+1}`. | Byte-identical to pqcrypto `_gammas`; length 128; `gammas[0] == 17`. |
| `invN` scaling | `128^{-1} mod 3329 = 3303` (ported `inv128`). | `(3303 * 128) % 3329 == 1`. |
| Status | L2–L3 green: roundtrip + basemul-vs-schoolbook for random and boundary polys; linearity green. | **complete (math)** |

**Normative algebra:** FIPS 203 ring \(\mathbb{Z}_{3329}[x]/(x^{256}+1)\).

### ML-DSA (\(q = 8380417\), \(n = 256\))

| Item | Source / notes | Verification |
|------|----------------|--------------|
| Twiddles | Port from `pqcrypto` `algos/dilithium/ntt.dart` (FIPS 204 Appendix B style). | `zetas[k] == 1753^bitrev8(k) mod q` generative formula matches; length 256; `zetas[0] == 1`. |
| `invN` | `256^{-1} mod 8380417 = 8347681` (ported from pqcrypto). | `(8347681 * 256) % 8380417 == 1`. |
| Status | L2–L3 green: roundtrip + pointwise basemul vs schoolbook for random and boundary polys; linearity green. | **complete (math)** |

**Normative algebra:** FIPS 204 ring \(\mathbb{Z}_{8380417}[x]/(x^{256}+1)\).

### FN-DSA / Falcon integer NTT (\(q = 12289\))

| Item | Source / notes | Verification |
|------|----------------|--------------|
| \(n = 512\), primitive root \(\psi = 49\), \(\psi^{512} \equiv -1\), \(\psi^{1024} \equiv 1\) | Falcon/FN-DSA integer NTT construction; `zetas[k] = ψ^{bitrev9(k)} mod q`. | `verify_constants.dart` regenerates all 512 zetas from ψ; `49^512 mod 12289 == 12288` (-1); `49^1024 mod 12289 == 1`. |
| \(n = 1024\), \(\psi = 7\), \(\psi^{1024} \equiv -1\), \(\psi^{2048} \equiv 1\) | Falcon/FN-DSA integer NTT construction; `zetas[k] = ψ^{bitrev10(k)} mod q`. | `verify_constants.dart` regenerates all 1024 zetas from ψ; `7^1024 mod 12289 == 12288` (-1); `7^2048 mod 12289 == 1`. |
| `invN` | `512^{-1} mod 12289 = 12265`; `1024^{-1} mod 12289 = 12277`. | `(12265 * 512) % 12289 == 1`; `(12277 * 1024) % 12289 == 1`. |
| Montgomery companions | `nPrime`, `r2` for q=12289 verified by mont identity tests. | `nPrime=12287`, `r2=10952`, `logR=16`; toMont/fromMont + montMul identities green. |
| Status | L2–L3 green: roundtrip + pointwise basemul vs schoolbook for random and boundary polys; linearity green. | **complete (math)** |

**Non-goals:** full FN-DSA signature scheme, FFT, discrete Gaussian sampling
(scheme package).

When parameters are finalized against the published FIPS 206 text, update this
row with exact clause/table citations and re-verify hashes or golden vectors.

---

## 3. Verification checklist (per table set)

```text
[ ] Length matches n (or n/2 for incomplete layers as designed)
[ ] invN * n ≡ 1 (mod q) for the scaling convention used
[ ] NTT then iNTT recovers random polys (canonical residues)
[ ] Optional: hash or pinned golden vector in test for regression
[ ] Source line in this register updated
[ ] README profile status updated only after L2–L3 green
```

---

## 4. Generation vs port

| Approach | When |
|----------|------|
| **Port** from `pqcrypto` | Path B continuity; preferred for ML-KEM/ML-DSA |
| **Generate** from \(\psi\), bit-reversal | FN-DSA or greenfield; must still pass roundtrip |
| **Hand-edit** single constants | Forbidden without re-running full profile tests |

Generator scripts, if added, live under `tool/` and are not required at
runtime.

---

## 5. Agent rule

```text
If you add or change a table:
  1. Update this register
  2. Add/adjust tests
  3. Do not mark complete in README without L2–L3
  4. Do not cite “FIPS validated tables”—cite algebraic source only
```

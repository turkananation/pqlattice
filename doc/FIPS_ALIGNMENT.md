# FIPS / Algorithm Alignment

Last updated: 2026-10-27

This document records how `pqlattice` relates to **NIST FIPS publications** and
named algorithms. It is **alignment of mathematical building blocks**, not
conformance of a complete cryptographic module or algorithm implementation.

| Standard | Name | Role of `pqlattice` |
| -------- | ---- | ------------------- |
| **FIPS 203** | ML-KEM | Integer ring \(q=3329\), \(n=256\); incomplete NTT; pair basemul; Barrett field reduce |
| **FIPS 204** | ML-DSA | Integer ring \(q=8380417\), \(n=256\); complete-style NTT; pointwise products |
| **FIPS 205** | SLH-DSA | **Out of scope** (hash-based; no lattice NTT in this package) |
| **FIPS 206** (FN-DSA / Falcon) | FN-DSA | Integer ring \(q=12289\), \(n\in\{512,1024\}\); integer NTT for verify-side math |

## What “adhere to FIPS” means here

**In scope for this library**

- Use the **same moduli and degrees** as the standards for the named presets.
- Implement NTT **shapes** consistent with how those standards multiply in
  \(\mathbb{Z}_q[x]/(x^n+1)\) (incomplete + pair basemul for ML-KEM; complete /
  pointwise for ML-DSA and FN-DSA integer paths).
- Prefer reduction techniques used in careful field code (Barrett for \(q=3329\)
  with tested parity against `%`).
- Cite FIPS algorithm names correctly in docs (ML-KEM not “Kyber” in normative
  claim text; FN-DSA for Falcon-derived FIPS 206).

**Out of scope (scheme / validation packages)**

- Full ML-KEM (K-PKE + Fujisaki–Okamoto), ML-DSA, FN-DSA, SLH-DSA.
- Byte encodings, sampling (CBD, etc.), SHAKE expand, KATs/ACVP.
- FIPS 140 / CMVP **module** validation.
- Floating-point FFT sampling for FN-DSA signing.

## Documentation rules

1. Prefer **ML-KEM / ML-DSA / FN-DSA / SLH-DSA** in normative text; “Kyber” /
   “Dilithium” / “Falcon” only as historical aliases.
2. Never state that `pqlattice` “implements FIPS 203” as a whole.
3. Allowed: “arithmetic for the FIPS 203 ring parameters \(q=3329\), \(n=256\)”.
4. FO transform: document only as belonging to ML-KEM in `pqcrypto`.
5. When zeta tables are added, source them from the standard appendices or
   byte-exact reference tables and lock them with tests.

## Parameter quick reference

| Profile | Standard | \(q\) | \(n\) | Product API |
| ------- | -------- | ----- | ----- | ----------- |
| `mlKem` | FIPS 203 | 3329 | 256 | `Basemul.mlKemPairs` |
| `mlDsa` | FIPS 204 | 8380417 | 256 | `Basemul.pointwise` |
| `fnDsa512` | FIPS 206 (FN-DSA) | 12289 | 512 | `Basemul.pointwise` |
| `fnDsa1024` | FIPS 206 (FN-DSA) | 12289 | 1024 | `Basemul.pointwise` |

See also [CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md), [API.md](API.md),
[FN_DSA_MATH.md](FN_DSA_MATH.md).

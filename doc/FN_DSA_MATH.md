# FN-DSA (Falcon / FIPS 206) Integer Math in `pqlattice`

Last updated: 2026-10-27

FN-DSA is NIST’s name for the Falcon-derived signature scheme (FIPS 206,
draft/approval path). This document defines **what lattice math belongs in
`pqlattice`** for FN-DSA and **what must stay in a scheme package** (e.g. future
`pqcrypto` FN-DSA module).

---

## 1. Integer ring (in scope)

| Symbol | FN-DSA-512 | FN-DSA-1024 |
| ------ | ---------- | ----------- |
| \(n\) | 512 | 1024 |
| \(q\) | 12289 | 12289 |
| Ring | \(\mathbb{Z}_q[x]/(x^n + 1)\) | same |

Presets:

- `RingParams.fnDsa512` / `RingParams.fnDsa1024`
- `NttParams.fnDsa512()` / `NttParams.fnDsa1024()` (zeta tables: ψ=49 / ψ=7, bit-rev powers)
- `MontgomeryParams.fnDsa` (R=2¹⁶, nPrime=12287, r2=10952) — correct implementation ready
- Barrett: `BarrettParams.fnDsa`

**Verified offline (2026-10-27):** ζ tables match independent generation from
ψ; NTT forward+inverse roundtrips for n=512 and n=1024; Montgomery reduce /
toMont/fromMont/montMul identity holds. FIPS 206 remains draft — integer
side only; no claim of final FIPS 206 KATs.

**Verification** of FN-DSA is essentially integer polynomial arithmetic modulo
\(q\) (NTT-based products with the public key polynomial \(h\), norm checks).
That path is a natural consumer of `pqlattice`.

Public-key form often uses **NTT(\(h\))**; keygen uses \(h = g \cdot f^{-1}\) in
the NTT domain. Those are **integer** operations → `NttEngine` + `Basemul.pointwise`
(complete-style NTT, not ML-KEM pair basemul).

---

## 2. What is **not** `pqlattice` (scheme / float domain)

| Component | Why out of scope |
| --------- | ---------------- |
| **FFT over \(\mathbb{C}\) / floating-point** | Falcon “Fast Fourier” sampling and LDL/Falcon tree use real/complex FFT, not \(\mathbb{Z}_q\) NTT |
| Discrete Gaussian / Fourier sampler | Signing trapdoor sampling |
| NTRUSolve (big-int / RNS multi-prime NTT, Babai reduce) | Keygen; may use *other* primes and multi-precision—not the single \(q=12289\) hot path alone |
| HashToPoint / SHAKE message map | Hash layer |
| Signature encode/decode, salt, accept bound \(\beta\) | Scheme packaging |
| Emulated vs native float policy (FIPS 206 discussions) | Implementation of signing, not ring math |

NIST materials emphasize that **keygen and signing** involve floating-point (or
approved fixed-point/emulated variants), which complicates validation and
side-channels. **Verification stays integer.** `pqlattice` optimizes the integer
side; it does not become a float FFT library.

---

## 3. API binding (recommended)

```dart
final ring = RingParams.fnDsa512; // or fnDsa1024
final ntt = NttEngine(ring, params: NttParams.fnDsa512());

// Integer domain
final hHat = ntt.forward(h);
final s2Hat = ntt.forward(s2);
final prod = Basemul.pointwise(hHat, s2Hat, ring); // complete NTT product
final s1 = ... // scheme reconstructs / checks using inverse NTT as specified
```

Do **not** use `Basemul.mlKemPairs` for FN-DSA.

Optional later (still integer, still in scope if needed by keygen helpers):

- Polynomial inversion modulo \(q\) in NTT domain (for \(f^{-1}\))
- Adjoint / conjugation helpers for ring \(\mathbb{Z}[x]/(x^n+1)\) **integer** forms used by some keygen steps

Multi-prime RNS NTT for NTRUSolve intermediates is **out of v0.1 scope**;
document as a future optional profile only if a scheme package needs shared
kernels.

---

## 4. Relation to ML-KEM / ML-DSA profiles

| Profile | \(q\) | \(n\) | NTT product |
| ------- | ----- | ----- | ----------- |
| ML-KEM | 3329 | 256 | **Pair basemul** (`Basemul.mlKemPairs`) |
| ML-DSA | 8380417 | 256 | Pointwise |
| FN-DSA | 12289 | 512 / 1024 | Pointwise |

Same `Poly` / `NttEngine` types; different `RingParams` + zeta tables + basemul
entry point.

---

## 5. Claims

- Allowed: “integer NTT and polynomial arithmetic for the FN-DSA ring \(q=12289\)”.
- Forbidden: “implements FN-DSA”, “FIPS 206 validated”, “constant-time Gaussian
  sampling”, “bit-exact float FFT”.

Scheme KATs / ACVP remain in the algorithm package.

---

## 6. Agent checklist (FN-DSA path)

1. Keep `RingParams.fnDsa512/1024` stable.
2. Path B: real zetas for \(n=512\) and \(n=1024\) mod 12289; round-trip NTT tests.
3. `Basemul.pointwise` + schoolbook oracle on toy or reduced degrees first.
4. Do not add `dart:ffi` float FFT “for Falcon” into this package.
5. When `pqcrypto` (or sibling) adds FN-DSA, verification should depend on
   `pqlattice` for \(q\)-NTT only.

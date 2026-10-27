**Primary rule:** see [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md) (OpenSSL / BoringSSL / liboqs / AWS-LC byte-exactness).

# Consumer API Shape & Migration from `pqcrypto` Internals

Last updated: 2026-10-27

**Audience:** `pqlattice` implementers and future `pqcrypto` maintainers who will
replace in-tree lattice arithmetic with this package while keeping KAT/ACVP
byte-exactness and claim boundaries.

Related: [ARCHITECTURE.md](ARCHITECTURE.md), [CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md),
[VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md), [AGENT_BRIEF.md](AGENT_BRIEF.md).

---

## 1. Layering (non-negotiable)

```text
┌─────────────────────────────────────────────────────────┐
│  pqcrypto (algorithm / scheme layer)                      │
│  • ML-KEM: K-PKE + Fujisaki–Okamoto (IND-CCA)             │
│  • ML-DSA: keygen / sign / verify, rejection, hints       │
│  • Packing, compress, CBD/sample, SHAKE expand            │
│  • KAT / ACVP evidence, public Kem/Dsa APIs               │
└──────────────────────────▲────────────────────────────────┘
                           │ uses only math primitives
┌──────────────────────────┴────────────────────────────────┐
│  pqlattice (math layer)                                   │
│  • Rings, ModQ, Barrett/(optional) Montgomery               │
│  • Poly / PolyVec / PolyMat                                 │
│  • NTT / iNTT / basemul / schoolbook oracle                 │
│  • Optional SIMD kernels                                    │
│  • NOT FO, NOT KEM, NOT signatures, NOT sampling hashes     │
└──────────────────────────▲────────────────────────────────┘
                           │ optional
┌──────────────────────────┴────────────────────────────────┐
│  zeroize — secret lifetime / narrow CT helpers              │
└───────────────────────────────────────────────────────────┘
```

**Fujisaki–Okamoto lives only in `pqcrypto`.** It is the re-encrypt-and-compare
transform that turns CPA K-PKE into CCA ML-KEM (FIPS 203 decapsulation: decrypt
→ re-encrypt → constant-time select of shared secret). That is **scheme logic**,
not polynomial arithmetic. `pqlattice` must not grow an FO API.

---

## 2. What `pqcrypto` owns today (math to replace later)

From `pqcrypto` architecture (develop):

| Location | Role | Migration target in `pqlattice` |
| -------- | ---- | -------------------------------- |
| `common/poly.dart` | ML-KEM polynomial arithmetic | `Poly`, `PolyOps`, ML-KEM NTT/basemul |
| `algos/dilithium/poly.dart` | ML-DSA poly/vector types | Separate ring profile (see §4) |
| `algos/dilithium/ntt.dart` | Complete NTT + Appendix B zetas | `NttEngine` + `NttParams` for ML-DSA ring |
| `algos/dilithium/rounding.dart` | Power2Round, Decompose, hints | **Prefer stay in pqcrypto** unless shared by ≥2 schemes |
| `algos/kyber/indcpa.dart` | K-PKE using poly/NTT | Stays in pqcrypto; **calls** pqlattice |
| `algos/kyber/kem.dart` | FO + public KEM API | Stays in pqcrypto |
| `algos/kyber/pack.dart` | ByteEncode/Decode, compress | Stays in pqcrypto (serialization) |

Design note already in pqcrypto: **ML-KEM and ML-DSA use different rings and NTT
shapes**—do not force one poly type for both.

| Scheme | \(q\) | \(n\) | NTT style |
| ------ | ----- | ----- | --------- |
| ML-KEM | 3329 | 256 | Incomplete; **basemul on degree-1 pairs** |
| ML-DSA | 8380417 | 256 | Complete; coefficient-wise products in NTT domain |

`pqcrypto` currently uses **no Montgomery domain** (Barrett-style / plain reduce
emphasis). `pqlattice` may add Montgomery later without forcing pqcrypto to use
it.

---

## 3. Proper API shapes (first-class consumer contract)

### 3.1 Principles

1. **Stable math, volatile schemes** — version NTT/basemul carefully; FO/Kem stay out.
2. **Ring profiles, not one true Poly** — `RingParams` + engine bound to a profile.
3. **In-place and allocating variants** where hot paths need it (`forwardInPlace`).
4. **Explicit domain** — coefficients in standard form vs NTT form must be
   documented (type aliases, naming, or dart doc)—do not mix silently.
5. **Fail closed** on wrong ring / wrong length.
6. **Bit-exact hooks for migration** — same zeta tables and reduction conventions
   as the path that passes KATs, or a documented dual until cutover.

### 3.2 Recommended public surface (target)

```dart
// Ring
RingParams.mlKem;           // q=3329, n=256
RingParams.mlDsa;           // q=8380417, n=256  (when ready)

// Modular
ModQ.reduce / add / sub / mul / freeze / csubq / center
BarrettParams.forQ(q)       // isReady when μ is real
// Montgomery optional, not required for parity with current pqcrypto

// Storage
Poly / PolyVec / PolyMat
PolyOps.addInto / subInto / negInto
RingMul.schoolbookNegacyclic  // oracle only

// Transform (per ring profile)
NttParams.mlKem() / NttParams.mlDsa()
NttEngine(ring, params: ..., mode: KernelMode.auto)
  .forward / .inverse
  .forwardInPlace / .inverseInPlace   // add when optimizing
  .forwardVec / .inverseVec

// NTT-domain product
Basemul.pointwise(...)           // full pointwise (ML-DSA-like)
Basemul.mlKemPair(...)           // FIPS 203 degree-1 pair basemul  ★ critical

// Policy
KernelMode / LatticeKernels
```

### 3.3 ML-KEM basemul shape (do not get this wrong)

Incomplete NTT for Kyber/ML-KEM multiplies **pairs** of coefficients with
twiddle-dependent formulas (basemul), not a naive \(c_i = a_i b_i\) for all
\(i\) unless the representation is defined that way end-to-end.

Migration requirement:

- Provide **`Basemul.mlKem` (or `basemulMontgomery` naming only if domain matches
  reference)** that matches FIPS 203 / current `pqcrypto` intermediate values.
- Keep a generic pointwise helper only where the NTT profile justifies it
  (ML-DSA).

### 3.4 What stays *out* of the public math API

| Concern | Owner |
| ------- | ----- |
| Fujisaki–Okamoto re-encrypt + CT select | `pqcrypto` kem/indcpa |
| CBD sampling, rejection sampling | `pqcrypto` + hash/XOF |
| `ByteEncode₁₂` / compress / decompress | `pqcrypto` pack |
| ExpandA / matrix from seed | `pqcrypto` (may call NTT on results) |
| Power2Round / MakeHint / UseHint | `pqcrypto` (ML-DSA) unless extracted later |
| Secure zeroization policy | `zeroize` + callers |
| KAT runners | `pqcrypto` test/ |

---

## 4. Dual-ring strategy

**Do not** merge ML-KEM and ML-DSA into one coefficient type with runtime switches
in the hot path.

Preferred:

```text
RingParams.mlKem  →  NttParams.mlKem  →  NttEngine  →  Basemul.mlKem pairs
RingParams.mlDsa  →  NttParams.mlDsa  →  NttEngine  →  Basemul.pointwise
```

Shared code: `ModQ` recipes, `Poly` storage layout helpers, SIMD policy,
schoolbook oracle parameterized by `RingParams`.

---

## 5. Migration stages (pqcrypto ← pqlattice)

| Stage | pqcrypto | pqlattice | Gate |
| ----- | -------- | --------- | ---- |
| **0 Scaffold** | Unchanged internal poly/NTT | Package exists | Path A tests |
| **1 Parity lab** | Still internal math | Real zetas + NTT + basemul | Intermediate-value or random vs schoolbook; optional tool comparing to pqcrypto internals |
| **2 Optional dep** | `dependency_overrides` / feature flag uses pqlattice behind indcpa | Stable API | Full ML-KEM KAT 3000/3000 still green |
| **3 Default** | indcpa/dilithium NTT call pqlattice | Versioned ^0.x | KAT + OpenSSL interop green; performance note |
| **4 Delete in-tree** | Remove duplicated poly/ntt | Only implementation | Claim boundary unchanged (still not FIPS 140) |

**Rule:** Never switch default until KAT/ACVP gates that already protect
`pqcrypto` still pass. Speed is secondary to byte-exact evidence.

---

## 6. Fujisaki–Okamoto (where it happens)

### 6.1 Location

**Only in the ML-KEM algorithm layer (`pqcrypto`).**

FIPS 203-style decapsulation (as documented in pqcrypto architecture):

```text
m'  ← K-PKE.Decrypt(sk, c)          // uses NTT/poly  →  may call pqlattice
K', r' ← G(m' ‖ H(pk))              // hash — not pqlattice
c'  ← K-PKE.Encrypt(pk, m', r')     // uses NTT/poly  →  may call pqlattice
K̄  ← J(z ‖ c)
K   ← CT_select(c == c', K', K̄)     // FO compare + select — NOT pqlattice
```

Encapsulation uses K-PKE encrypt once; FO’s defining **re-encryption check** is
on the decapsulation path.

### 6.2 What FO needs from the math layer

- Correct, deterministic K-PKE encrypt/decrypt arithmetic (NTT, basemul, reduce).
- No FO-specific API.
- Optional: CT-friendly compare of **byte** ciphertexts stays in kem (or
  `zeroize` CT helpers)—not inside NTT.

### 6.3 What FO must never become

- A method on `NttEngine` or `Poly`.
- A reason to pull SHAKE/G into `pqlattice`.
- A performance excuse to break KAT determinism.

---

## 7. Adjacent edge cases (often forgotten)

| Edge case | Guidance |
| --------- | -------- |
| **NTT domain vs normal domain** | Document output order (bit-reversed vs normal). Match pqcrypto/FIPS tables. |
| **Montgomery vs standard domain** | Current pqcrypto: no Montgomery. If pqlattice adds it, conversions must be explicit; KAT path must agree. |
| **Lazy reduction bounds** | Document max \|coeff\| before forced reduce; stay in `int`. |
| **Inverse NTT scale** | \(n^{-1} \bmod q\) placement (merged into last layer vs separate pass). |
| **Basemul pair indexing** | Off-by-one vs FIPS 203 is a classic KAT breaker. |
| **Signed vs unsigned coeffs** | ML-DSA uses larger \(q\) and signed-centered norms; freeze/center conventions differ from ML-KEM. |
| **In-place aliasing** | `forwardInPlace(p)` must define overlap rules. |
| **PolyVec length vs scheme \(k\)** | Math layer does not know \(k\); scheme passes dimensions. |
| **Secret vs public polys** | Math is agnostic; callers zeroize secrets via `zeroize`. |
| **Web (JS/Wasm)** | Same API; no SIMD assumptions; KAT may be VM-only for huge corpora. |
| **Determinism** | Same inputs → same coeffs (no ambient randomness in math). |
| **Constant-time structure** | Best-effort only; FO’s CT select stays in kem. |
| **Version skew** | pqcrypto pins pqlattice version when dependent; changelog must flag NTT semantic breaks as breaking. |
| **Zero poly / sparse poly** | Schoolbook and NTT must handle; sparse optimisations are optional and must not change results. |
| **q=3329 Barrett μ** | Must be tested against `%` before KAT migration. |
| **Dilithium zetas Appendix B** | Separate table from ML-KEM; wrong table = silent total break. |

---

## 8. Documentation set (first-class)

| Doc | Role |
| --- | ---- |
| `CLAIM_BOUNDARY.md` | Not FIPS 140; not “implements ML-KEM” |
| `VM_COMPILER_BOUNDARY.md` | No auto-vectorization reliance; SIMD optional |
| `ARCHITECTURE.md` | Module jurisdictions |
| `AGENT_BRIEF.md` | Implementation paths A–D |
| **`CONSUMER_API_AND_MIGRATION.md` (this file)** | How pqcrypto will consume; FO placement; edge cases |
| Future: `NTT_BOUNDS.md` | Lazy-reduce proofs / intermediate limits |
| Future: `INTEROP_PQCRYPTO.md` | Intermediate-value vectors shared for parity |

---

## 9. Success criteria for “replaces pqcrypto math”

1. `Basemul.mlKem` + ML-KEM NTT match current pqcrypto (or FIPS) intermediates on
   a checked corpus of random polys / known vectors.
2. ML-KEM KAT 3000/3000 still pass with indcpa delegated to pqlattice.
3. ML-DSA KAT still pass when Dilithium NTT is delegated (separate profile).
4. Public `pqcrypto` API unchanged (Kem/Dsa only).
5. Claims still evidence-scoped; FO still only in kem/decaps.
6. Performance: measured on **AOT** release builds; documented, not assumed.

---

## 10. One-sentence summary

**`pqlattice` is the fast, tested ring/NTT/basemul engine; `pqcrypto` remains the
FIPS-aligned scheme layer including Fujisaki–Okamoto, packing, sampling, and
KAT evidence—replacement is a staged dependency cutover, not a merge of FO into
the math package.**


---

## 11. FN-DSA (Falcon / FIPS 206)

Integer math for FN-DSA is a **first-class ring profile** in `pqlattice`:

- `RingParams.fnDsa512` / `fnDsa1024` — \(q = 12289\), \(n \in \{512, 1024\}\)
- `NttParams.fnDsa512()` / `fnDsa1024()` — complete-style integer NTT
- Product: `Basemul.pointwise` (not `mlKemPairs`)

**Out of `pqlattice`:** complex/real FFT, LDL/Falcon tree, discrete Gaussian
sampling, full NTRUSolve/RNS keygen, HashToPoint. Those belong in the FN-DSA
scheme implementation.

**FO does not apply** to FN-DSA (signatures, not KEMs). FN-DSA verification is
the primary early consumer of integer NTT; signing float-domain work stays out.

See [FN_DSA_MATH.md](FN_DSA_MATH.md).

## API reference

Normative public surface summary: [API.md](API.md). This migration doc remains the cutover and FO/FN-DSA boundary narrative.

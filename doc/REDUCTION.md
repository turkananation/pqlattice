# Modular Reduction (Barrett, Montgomery, Lazy Bounds)

Last updated: 2026-10-27

Single source of truth for **how** `pqlattice` reduces modulo \(q\), what
parameters mean, and how that interacts with **interop**.

Related: [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md),
[ACCELERATION.md](ACCELERATION.md), [FIPS_ALIGNMENT.md](FIPS_ALIGNMENT.md),
[TESTING.md](TESTING.md).

Code: `lib/src/mod/barrett_params.dart`, `montgomery_params.dart`, `mod_q.dart`.

---

## 1. Goals

| Goal | Policy |
|------|--------|
| Speed | Barrett (and Montgomery where appropriate) are **default accelerated** field ops—not optional “fast mode.” |
| Correctness | Public results match reference `mod q` on the **canonical residue range** the API documents (typically \([0,q)\)). |
| Interop | Substituting these ops into `pqcrypto` must not change wire bytes or interop locks. |
| Honesty | Document lazy intermediates; do not pretend every partial product is fully reduced. |

---

## 2. Canonical residues

Unless a method is explicitly named `*Fast` / `lazy*`:

- Outputs of public reduce APIs are in **\([0, q)\)**.
- Centered representatives (e.g. \([-(q-1)/2, (q-1)/2]\)) are **opt-in** helpers
  and must be named as such (`center`, `freeze` style)—never silently mixed
  into NTT tables that expect unsigned residues.

Interop paths that match OpenSSL / liboqs style intermediates must use the
**same** representative conventions as the `pqcrypto` path being replaced.

---

## 3. Barrett reduction

### 3.1 Idea

For modulus \(q\), precompute \(\mu \approx \lfloor 2^{k}/q \rfloor\) for a
shift \(k\) large enough relative to the maximum input magnitude. Approximate
quotient, multiply back by \(q\), subtract, then a small number of conditional
corrections.

### 3.2 Parameters (`BarrettParams`)

| Field | Meaning |
|-------|---------|
| `q` | Modulus |
| `mu` | Barrett multiplier |
| `shift` | Right-shift after `mu` multiply (notation may be `k` in literature) |
| `isReady` | Params are valid for hot path |

Presets live in `BarrettParams.forQ` / profile helpers:

| \(q\) | shift | \(\mu\) | Notes |
|-------|-------|---------|--------|
| 3329 | 24 | 5039 | ML-KEM; covers residue products |
| 12289 | 24 | 1365 | FN-DSA integer ring |
| 8380417 | **48** | 33587228 | ML-DSA; **shift 32 is insufficient** for \(q^2\) products |

### 3.3 Implementation rules

1. **Parity:** `reduceBarrett(x) ≡ x (mod q)` and result in canonical range
   for all tested inputs in the **documented input bound**.
2. **Input bound:** Document max \(|x|\) (or unsigned max) the recipe accepts
   without extra reduction rounds. NTT butterflies must respect that bound or
   reduce more often.
3. **No BigInt** on the hot path.
4. **Fused mul-reduce** (`mulBarrett`) preferred in basemul when it preserves
   parity and bound discipline.
5. **Interop:** If `pqcrypto` uses a specific Barrett width or correction
   pattern for ML-KEM, port that pattern rather than a “better” but divergent
   recipe when Path B substitution is the goal.

### 3.4 What interop means for Barrett

Changing \(\mu\), shift, or the number of final `csubq` steps is **allowed
only if** every public poly/NTT output still matches the interop oracle.
Internal intermediate registers may differ **only** if no consumer observes
them and final residues match. Prefer matching the proven path’s correction
style to minimize surprise in L5 intermediate locks.

---

## 4. Montgomery reduction

### 4.1 Idea

Work in domain \(aR \bmod q\) with radix \(R = 2^{w}\) (this package targets
**\(w = 16\)** for small \(q\) paths where documented—see
`MontgomeryParams`). Multiplication uses \(n' = -q^{-1} \bmod R\) and
conversion factors \(R^2 \bmod q\).

### 4.2 Parameters (`MontgomeryParams`)

| Field | Meaning |
|-------|---------|
| `q` | Modulus |
| `nPrime` | \(-q^{-1} \bmod R\) |
| `r2` | \(R^2 \bmod q\) |
| `R` / width | Implicit from recipe (document per preset) |

Example posture for FN-DSA-scale \(q = 12289\): constants must be **verified**
against the identity `fromMont(toMont(a)) ≡ a` and
`fromMont(montMul(toMont(a), toMont(b))) ≡ ab (mod q)`.

### 4.3 Implementation rules

1. Domain is **explicit**: values in Montgomery form must not be mixed with
   plain residues in public APIs without conversion.
2. Default **public** poly APIs remain in plain \(\mathbb{Z}_q\) unless a type
   or method name says otherwise.
3. Scaffold code must not be enabled as default until L1 tests pass for that
   `q`.
4. Same interop rule as Barrett: final observable residues match the locked
   path.

### 4.4 When to use Barrett vs Montgomery

| Situation | Preference |
|-----------|------------|
| Sparse reductions, general poly add/sub | Barrett or cheap conditional sub |
| Dense mul chains inside NTT/basemul | Profile-specific; measure AOT; parity first |
| Matching existing `pqcrypto` ML-KEM path | Follow that path’s reduce (often Barrett-style) |

Acceleration means **using** these recipes by default—not leaving `%` on the
hot path once a recipe is ready.

---

## 5. Lazy reduction

NTT layers may delay full reduction so intermediates grow. Document per
profile:

| Profile | \(q\) | Notes on growth |
|---------|-------|-----------------|
| ML-KEM | 3329 | Incomplete NTT; follow Kyber-style bounds used in ported loops |
| ML-DSA | 8380417 | Larger headroom; still no BigInt |
| FN-DSA | 12289 | Integer NTT; keep products within documented mont/barrett input bound |

**Rule:** If a butterfly can exceed the reduce recipe’s input bound, insert a
reduce (or use a wider intermediate strategy that is still pure `int` and
tested).

---

## 6. Conditional subtract (`csubq`) / freeze

- After approximate Barrett, one or two subtract-if-≥\(q\) steps are normal.
- Prefer **branchless** style where it does not harm clarity *and* is tested;
  do not claim constant-time execution on all backends
  ([SECURITY_POSTURE.md](SECURITY_POSTURE.md)).
- `freeze` / center maps to centered reps only when the scheme layer needs
  them; lattice math APIs default to \([0,q)\).

---

## 7. API surface (conceptual)

```text
ModQ.reduceBarrett / mulBarrett / addFast / subFast
ModQ.montReduce / montMul / toMont / fromMont
BarrettParams.forQ / profile presets
MontgomeryParams.forQ / profile presets
```

Public `Poly` / `NttEngine` entry points should not require callers to pick
μ by hand; presets bind to `RingParams`.

---

## 8. Test expectations

See [TESTING.md](TESTING.md) L1. Minimum:

- Random and edge parity vs `%` / reference for each ready `q`.
- Montgomery roundtrip identity.
- No default path using incomplete Montgomery scaffold.

---

## 9. Agent rules

```text
[ ] Never “optimize” reduce without parity tests
[ ] Never change canonical range without API + interop review
[ ] Never enable Mont default without L1 green for that q
[ ] Document input bounds when changing butterfly reduce frequency
[ ] Interop conflict → revert reduce change
```

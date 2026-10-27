# Primary Rule: Byte-Exact Interop & FIPS Adherence

Last updated: 2026-10-27

## The rule (non-negotiable)

**`pqcrypto` is byte-exact interoperable with OpenSSL, BoringSSL, liboqs, and
AWS-LC** (and stays aligned with the relevant FIPS algorithm specifications).

Any math that `pqlattice` supplies for use by `pqcrypto` **must preserve that
property**.

1. **Do not change** wire bytes, KATs, or cross-library interop vectors that
   `pqcrypto` already matches.
2. **Do not “improve”** NTT, basemul, reduction, or packing math in a way that
   alters intermediates or outputs relative to the path that passes interop.
3. **FIPS algorithm specs** (FIPS 203 / 204 / 206 integer side, etc.) define the
   normative algebra; interop libraries are the **empirical lock** that the
   implementation is still in the same equivalence class.
4. **`pqlattice` is not a FIPS 140 module** and does not replace scheme-layer
   evidence. It must still be **safe to substitute** under `pqcrypto` without
   breaking OpenSSL / BoringSSL / liboqs / AWS-LC byte agreement.

If speed and interop conflict, **interop wins**. Optimize only with parity
tests against the current `pqcrypto` (or shared intermediate vectors) on the
same profile.

---

## What “byte-exact” binds

| Layer | Who owns the lock | `pqlattice` duty |
| ----- | ----------------- | ---------------- |
| ML-KEM encaps/decaps ciphertext & shared secret | `pqcrypto` + interop harnesses | NTT / basemul / field ops must match the math that produces those bytes |
| ML-DSA keys / signatures | `pqcrypto` + interop | Same for Dilithium NTT / poly ops when ported |
| FN-DSA (when present) | scheme package + interop | Integer \(q\)-NTT must match verify-side references |
| FO, sampling, packing, SHAKE | `pqcrypto` only | Never reimplement here |

Tables and loop shapes ported from `pqcrypto` (e.g. ML-KEM zetas / gammas /
NTT) exist **to keep continuity** with that interop-proven path—not to invent a
second algebra.

---

## FIPS adherence (how it interacts)

- **Normative names and parameters:** FIPS 203 (ML-KEM), FIPS 204 (ML-DSA),
  FIPS 206 (FN-DSA) integer rings — see [FIPS_ALIGNMENT.md](FIPS_ALIGNMENT.md).
- **Evidence of scheme correctness:** remains in `pqcrypto` (KAT/ACVP +
  OpenSSL / BoringSSL / liboqs / AWS-LC interop).
- **This package:** field/NTT **alignment** only; no “FIPS validated module”
  claims ([CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md)).

Adhering to FIPS does **not** mean diverging from interop-proven code to match
a different textbook pseudocode. Prefer the variant that `pqcrypto` already
locks to the ecosystem.

---

## Gates before `pqcrypto` defaults to `pqlattice`

1. Intermediate or full-path parity vs current `pqcrypto` math on ML-KEM (and
   ML-DSA when ported).
2. Existing `pqcrypto` KAT suites still green.
3. Existing interop suites vs OpenSSL / BoringSSL / liboqs / AWS-LC still green
   (as maintained under `pqcrypto` `tool/` / CI).
4. No silent change to reduction domain, zeta layout, or basemul indexing.

---

## Agent / PR checklist

- [ ] Change preserves or improves parity with `pqcrypto` tables/loops where
      ported from there
- [ ] No alternate NTT “cleanup” that fails schoolbook or pqcrypto comparison
- [ ] README/docs do not claim interop for `pqlattice` alone
- [ ] Scheme interop remains the release gate for cutover

**One line:** *FIPS-aligned algebra, ecosystem byte-exactness locked by
`pqcrypto` interop—`pqlattice` must not break either.*

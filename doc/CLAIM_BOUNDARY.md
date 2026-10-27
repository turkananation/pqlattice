# Claim Boundary

Last updated: 2026-10-27

This document is the permanent record of what `pqlattice` may and may not claim.
Every public README, pubspec description, release note, and agent-facing file
must stay inside this boundary.

## Two different claims

| Claim | Question | What pqlattice has (0.1.x) |
| ----- | -------- | ------------------------- |
| **Mathematical / structural alignment** | Do the rings, NTT shapes, and modular ops match the algebra used by lattice PQC (e.g. FIPS 203/204 style parameters)? | Target: yes, with unit tests for reduction, NTT invertibility, and parameter tables. |
| **Algorithm / KAT conformance for a NIST standard** | Is this a byte-exact ML-KEM or ML-DSA implementation? | **No.** That is `pqcrypto`. |
| **Module validation (FIPS 140 / CMVP)** | Is this a validated cryptographic module with a certificate? | **No.** Pure Dart libraries are not CMVP modules. |

## Allowed wording

- Pure-Dart lattice and polynomial arithmetic (NTT, inverse NTT, basemul, modular reduction).
- Algebraic structure aligned with rings used by FIPS 203 (ML-KEM) and FIPS 204 (ML-DSA) parameter sets.
- Optional SIMD-aware kernels with a scalar fallback that is always available.
- Unit-tested properties (e.g. NTT round-trip, reduction bounds) as evidence of correctness of the **math layer**.
- Best-effort performance; measure on AOT release builds for production claims about speed.
- Best-effort constant-time *source structure* where documented; not a hard timing guarantee on VM/JS/Wasm.

## Forbidden wording

- “FIPS validated”, “FIPS 140 validated”, “FIPS 140-3 compliant module”
- “CMVP validated”, “CAVP certified”, “certified”, “fully certified”
- “Implements ML-KEM” / “implements ML-DSA” / “implements Kyber/Dilithium” as a **full algorithm** (use `pqcrypto`)
- “Guaranteed constant-time on all platforms”
- “Secure erasure guaranteed” / “secrets are wiped from memory”
- “NIST KAT byte-exact” for a full standardized algorithm until such evidence is checked in and gated

## Dependency on evidence

When NTT or modular routines are later proven byte-compatible with a specific
reference (e.g. matching intermediate values from a pqcrypto or PQClean path),
document that as **interop or intermediate-value evidence**, not as module
validation. Prefer linking a short evidence note under `doc/` rather than
inflating README badges.

## Side channels and zeroization

- Timing and cache side-channel resistance in pure Dart is **best-effort**.
- Coefficient buffers should be zeroed when handed to higher layers that use
  `zeroize`; this package may offer hooks but does not replace `zeroize`.
- Do not claim mlock-style or OS-backed secret memory.

## Inheritance

Higher packages (`pqcrypto`, `pqforge`, …) may say they use `pqlattice` for
polynomial arithmetic. They must not upgrade that into FIPS 140 or “certified
NTT” language.

## Fujisaki–Okamoto

`pqlattice` does not implement FO or any IND-CCA wrapper. That transform belongs
in the ML-KEM implementation (`pqcrypto`). Claiming "CCA-secure KEM" from this
package alone is **forbidden**.

## FN-DSA / Falcon

Allowed: integer modular polynomial arithmetic and NTT for the FN-DSA ring
(\(q=12289\), \(n=512\) or \(1024\)).

Forbidden wording: "implements FN-DSA", "FIPS 206 module", "validated floating-point
FFT sampler". Float-domain signing and keygen policy remain outside this package.

## FIPS standards vs this package

Parameter and algebraic **alignment** with FIPS 203 / 204 / 206 (integer FN-DSA)
is described in [FIPS_ALIGNMENT.md](FIPS_ALIGNMENT.md). Alignment of rings and
NTT shape is not algorithm conformance and not FIPS 140 validation.

## Interop ownership

Byte-exact interop with OpenSSL, BoringSSL, liboqs, and AWS-LC is a **pqcrypto**
property and release gate. `pqlattice` must not ship math that would break those
vectors when substituted. See [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md).

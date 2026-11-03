---
title: Security posture
description: What pqlattice guarantees (byte-exact interop, fail-closed surfaces, exhaustive proofs) and what it deliberately does not promise (constant time, memory wiping, scheme logic).
keywords:
  - pqlattice security
  - post-quantum Dart security
---

Honest guarantees beat comfortable ambiguity. This page states both columns.

## What this package promises

- **Byte-exact interop** with OpenSSL / BoringSSL / liboqs references on the
  rings and profiles it targets (the interop rule is the outermost
  constraint; if performance conflicts with byte agreement, agreement wins).
- **Determinism** — math APIs take all entropy from callers; no ambient
  randomness, no hidden state in NTT or reduce.
- **Fail-closed bounds** — missing/unfinished machinery throws; coercions and
  silent fallbacks are being structurally refuted.
- **Proven bounds, not folklore** — reduce recipes carry documented
  intermediate-magnitude bounds, certified exhaustively over full modulus
  squares where possible (ML-KEM 3329², FN-DSA 12289²).
- **Scope discipline** — no scheme logic (no FO, no hashing-to-point), no
  KAT corpora, no sampling, by design. Errors of that class are rejected at
  review, not caught at runtime.

## What it does not promise

- **No constant-time guarantee** — Dart VM/JS/Wasm do not offer a
  platform-level timing boundary the library could honestly bind to;
  branch-light structure is intended where it matters, and is stated as
  intent, not as an observable guarantee.
- **No secret-material guarantees** — memory wiping (zeroize and the like) is
  the caller's job; avoid logging secret polynomials (coefficients of secret
  polys are never printed by library code).
- **Not a FIPS 140 module** — no validation program claim, no building as a
  validated cryptographic module vocabulary.

## How to use it sensibly

Treat `site`/library outputs as algebraic results you can pin and test, not as
a defense-in-depth curated runtime. If you embed it in a scheme
implementation, the scheme package owns scheme-level security decisions and
side-channel posture.

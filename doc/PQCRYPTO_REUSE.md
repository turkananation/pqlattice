**Constraint:** ports exist to preserve `pqcrypto` byte-exact interop with
OpenSSL, BoringSSL, liboqs, and AWS-LC—not to invent a second ML-KEM algebra.
See [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md).

# Reuse from `pqcrypto`

Last updated: 2026-10-27

## Lifted into `pqlattice` (correct, KAT-backed lineage)

| Asset | pqcrypto source | pqlattice home |
| ----- | --------------- | -------------- |
| ML-KEM zetas (128) | `algos/kyber/poly.dart` `_zetas` | `ntt/mlkem_tables.dart` |
| ML-KEM gammas (128) | same, `_gammas` | same |
| inv128 = 3303 | `Poly.invNtt` | `NttParams.invNScale` |
| NTT / invNTT loop shape | `Poly.ntt` / `invNtt` | `NttEngine` ML-KEM path |
| Pair basemul | `Poly.baseMul` | `Basemul.mlKemPairs` |

These tables match FIPS 203 / Go-style unsigned zetas used by pqcrypto’s
ML-KEM path (KAT-validated at the scheme layer).

## Next ports (do not invent)

| Asset | pqcrypto source | Notes |
| ----- | --------------- | ----- |
| ML-DSA zetas | `algos/dilithium/ntt.dart` | Complete NTT; different \(q\) |
| ML-DSA inv scale 8347681 | same | \(256^{-1} \bmod q\) |
| Field Barrett constants | `Poly.barrettReduce` uses \(\mu=20159\), shift 26 | Optional parity with pqcrypto; our \(5039/24\) is also a standard recipe — keep tests vs `%` |

## Do **not** port into `pqlattice`

- `indcpa.dart` / FO / kem API
- CBD sampling, packing, SHAKE expand
- Dilithium rounding / hints / SampleInBall
- `zeroize.dart` (use package `zeroize`)
- Keccak / SHA-2

## Integer / coefficient model

pqcrypto uses `List<int>` coefficients and plain `int` field ops — **reuse that
model**, not a new class tower. See `lib/src/mod/coeff.dart` (`Coeff`,
`CoeffList` typedefs) and AGENTS.md.

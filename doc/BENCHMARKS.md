# Benchmarks

Last updated: 2026-10-27

How to measure and **claim** performance for `pqlattice` without misleading
users or agents.

Related: [ACCELERATION.md](ACCELERATION.md), [SIMD.md](SIMD.md),
[SDK_SIMD_TRACKING.md](SDK_SIMD_TRACKING.md), [AGENTS.md](../AGENTS.md).

---

## 1. Rules for claims

1. **AOT counts.** Production-relevant claims use `dart compile exe` (or
   Flutter release), not only `dart run` JIT.
2. **Parity first.** Never publish a “faster” kernel that fails scalar/SIMD
   residue parity.
3. **Report context:** profile (`mlKem` / `mlDsa` / `fnDsa*`), `KernelMode`,
   OS, CPU, Dart SDK version, JIT vs AOT.
4. **No auto-vectorization claims.** Speedups come from algorithms + explicit
   kernels, not “the VM vectorized our loop.”
5. **Interop > speed.** If a faster reduce breaks interop locks, it does not
   ship.

---

## 2. In-tree harness

Primary entry (as present in tree):

```text
tool/bench/ntt_bench.dart
```

Typical measurements:

- NTT forward / inverse (allocating vs in-place)
- NTT + basemul pipeline
- Optional: Barrett mul vs reference `%` (micro)

Run examples:

```bash
# JIT (dev only — do not use alone for public claims)
dart run tool/bench/ntt_bench.dart

# AOT (required for claim-quality numbers)
dart compile exe tool/bench/ntt_bench.dart -o /tmp/pqlattice_ntt_bench
/tmp/pqlattice_ntt_bench
```

Pin a warm-up + measurement loop style inside the tool; prefer fixed iteration
counts and median or best-of-N over single shots.

---

## 3. What to record in a PR

```text
SDK:          3.x.y
Mode:         AOT exe
Host:         e.g. linux x64 / apple silicon
Profile:      mlKem | mlDsa | fnDsa512 | ...
KernelMode:   accelerated | optimizedScalar | simd | reference
Op:           nttFwd | nttInv | ntt+basemul | barrettMul
n / q:        from RingParams
ns/op or us/op: ...
Notes:        e.g. "SIMD shape, scalar lane mul"
```

Compare **same machine** before/after. Cross-machine comparisons are anecdotal
only.

---

## 4. Microbench hygiene

- Prevent DCE: accumulate a sink (XOR of a coefficient or similar).
- Separate **setup** (poly allocation, table touch) from timed region.
- For in-place APIs, do not count outer allocation in the timed loop.
- When testing SIMD, also run optimized scalar on the same build.

---

## 5. Interpreting results

| Observation | Interpretation |
|-------------|----------------|
| JIT ≫ AOT for `Int32x4` | Known class of issues; track SDK fixes; don’t claim AOT win |
| Accelerated ≈ reference | Recipe not on hot path or bound too tight; investigate |
| SIMD shape ≤ scalar | Expected until pairwise mul; still OK if parity holds |
| Faster but parity fail | **Reject** |

---

## 6. CI posture

- CI should run **correctness** tests always.
- Optional nightly/job: AOT bench smoke (does not fail on noise without a
  regression policy).
- Formal regression thresholds only after a stored baseline exists per
  primary profile.

### Baseline results (AOT, `dart compile exe`)

| SDK | Mode | Host | Profile | Op | µs/op | Notes |
|-----|------|------|---------|-----|-------|-------|
| 3.13.5 | AOT exe | linux x64 | mlKem | ntt+basemul+inv | 204.6 | 2000 iters, `KernelMode.accelerated` |
| 3.13.5 | AOT exe | linux x64 | mlKem | in-place ntt+basemul+inv | 194.3 | 2000 iters, `KernelMode.accelerated` |
| 3.13.5 | AOT exe | linux x64 | mlKem | in-place ntt+basemul+inv | 172.9 | pre-stage chains, 1000 iters x 5 rounds |
| 3.13.5 | AOT exe | linux x64 | mlDsa | in-place ntt+basemul+inv | 332.9 | pre-stage chains, 1000 iters x 5 rounds |
| 3.13.5 | AOT exe | linux x64 | fnDsa512 | in-place ntt+basemul+inv | 629.5 | pre-stage chains, 1000 iters x 5 rounds |
| 3.13.5 | AOT exe | linux x64 | fnDsa1024 | in-place ntt+basemul+inv | 1403.4 | pre-stage chains, 1000 iters x 5 rounds |
| 3.13.5 | AOT exe | linux x64 | mlKem | in-place ntt+basemul+inv | 142.6 | post-stage inlined chains, 1000 iters x 5 rounds |
| 3.13.5 | AOT exe | linux x64 | mlDsa | in-place ntt+basemul+inv | 158.1 | post-stage inlined chains, 1000 iters x 5 rounds |
| 3.13.5 | AOT exe | linux x64 | fnDsa512 | in-place ntt+basemul+inv | 388.4 | post-stage inlined chains, 1000 iters x 5 rounds |
| 3.13.5 | AOT exe | linux x64 | fnDsa1024 | in-place ntt+basemul+inv | 837.4 | post-stage inlined chains, 1000 iters x 5 rounds |

These are machine-specific smoke numbers, not portable speed claims.

---

## 7. Benchmark harness and variation matrix

### 7.1 Harness design (trustworthy, not a hack)

The harness lives under `test/benchmarks/` and is **dependency-free pure Dart** — no `benchmark_harness` package, no `zeroize` repurposing, no FFI. Every measurement follows these rules, which are binding for any result presented as a claim:

| Rule | Implementation |
|------|---------------|
| **AOT-first** | Numbers are meaningful only from `dart compile exe`. JIT is recorded separately for variance documentation only (doc/VM_COMPILER_BOUNDARY.md §3). |
| **Warm-up mandatory** | 200 warm-up iterations before every timed region (JIT compilation, optimizer settling, table touches). |
| **Multiple rounds, median reported** | 5 rounds × 1000 iterations each; median per-iteration nanoseconds reported. Single-shot timing is not a valid claim (doc/BENCHMARKS.md §1 rule 2). |
| **DSE defeated** | A `@pragma('vm:never-inline')` opaque sink is XORed with a result coefficient after every timed iteration; the sink value is returned at the end so the compiler cannot prove the loop dead (same mechanism as `zeroize`'s `dse_guard.dart`, implemented locally to avoid a dependency). |
| **Setup separate from timing** | Engine/poly/table construction happens outside the timed region. |
| **Deterministic inputs** | Fixed-seed pseudo-random polys; no `Random`, `DateTime`, or I/O inside the timed loop. |
| **No date stamps** | Traceability is via git commit SHA, not dates (doc/AGENTS.md hard rule 2). |
| **Full context on every row** | SDK version, OS, CPU count, `KernelMode`, profile, q, n, reduce strategy, layout, domain, build mode, iterations, rounds, warm-up, mean/median/min/max/stdDev, rstd%, sink. |

### 7.2 How to run

```bash
# JIT (dev only — not for public speed claims)
dart run test/benchmarks/benchmarks_all.dart

# AOT (required for claim-quality numbers)
dart compile exe test/benchmarks/benchmarks_all.dart -o /tmp/pq_bench
/tmp/pq_bench
```

Output is TSV on stdout, one row per measurement, with a header line. Pipe to a file for CI artifacts:

```bash
/tmp/pq_bench > benchmarks-$(git rev-parse --short HEAD).tsv
```

### 7.3 Variation matrix

Every benchmark suite covers the full Cartesian product that is meaningful for that op:

| Dimension | Values |
|-----------|--------|
| Profile | `mlKem` (q=3329, n=256), `mlDsa` (q=8380417, n=256), `fnDsa512` (q=12289, n=512), `fnDsa1024` (q=12289, n=1024) |
| Op | `forward`, `inverse`, `forward+inverse`, `forwardInPlace`, `inverseInPlace`, `pointwise`, `mlKemPairs`, `reduceBarrett`, `reducePercent`, `montMul`, `montReduce`, `ntt+basemul+inv` |
| KernelMode | `accelerated` (default), `optimizedScalar`, `simd`, `reference` |
| Reduce strategy | `barrett`, `percent`, `montgomery` |
| Layout | `allocating`, `inPlace` |
| Domain | `plain`, `montgomery` |
| Build mode | `jit` (`dart run`), `aot` (`dart compile exe`) |

Not all combinations are meaningful (e.g. `reference` mode with Montgomery is contradictory). The harness skips invalid combinations and records them as skipped rather than producing misleading numbers.

### 7.3.1 Suites

| Suite | File | What it measures |
|-------|------|------------------|
| `ntt` | `test/benchmarks/ntt_benchmarks.dart` | Forward / inverse / forward+inverse, allocating + in-place, plain + Montgomery, all 4 profiles |
| `basemul` | `test/benchmarks/basemul_benchmarks.dart` | Pointwise (ML-DSA/FN-DSA) and mlKemPairs (ML-KEM), allocating + in-place, plain + Montgomery |
| `reduce` | `test/benchmarks/reduce_benchmarks.dart` | `reduceBarrett` vs `reducePercent` vs `montMul` vs `montReduce`, per modulus |
| `pipeline` | `test/benchmarks/pipeline_benchmarks.dart` | Full NTT→basemul→invNTT, allocating + in-place, plain + Montgomery, all 4 profiles |
| `simd` | `test/benchmarks/simd_parity_benchmarks.dart` | SIMD-shaped pointwise vs scalar pointwise timing (speed only — correctness parity is the test suite's job) |
| `polyvec` | `test/benchmarks/polyvec_benchmarks.dart` | PolyVec construct/clone/indexing, PolyMat construct/at/setAt, forwardVec, all 4 profiles + toy rings |
| `schoolbook` | `test/benchmarks/schoolbook_benchmarks.dart` | Negacyclic schoolbook product (L0 oracle), toy rings (n=4/8/16) and FIPS profiles at full size |

### 7.4 CI posture

- Correctness tests (`dart test`) always run — benchmarks do not gate merge.
- Benchmarks run on a **dedicated nightly job** on a pinned machine image.
- **No regression thresholds** until a stored baseline exists per primary profile (see §6 baseline table).
- Results stored as TSV artifacts with git commit SHA for traceability.

### 7.5 Missing benchmarks

The following benchmarks are **not yet implemented**. Do not claim results for them until they exist and are green:

| Missing benchmark | Why it matters | Blocker |
|-------------------|---------------|---------|
| **pqcrypto side-by-side** | Run the identical NTT+basemul+inv workload through `pqcrypto`'s internal `Poly.ntt`/`baseMul` on the same machine, same AOT flags. This is the **only** way to claim speed relative to pqcrypto. pqcrypto is a separate repo; its benchmarks have not been executed against pqlattice. | Cross-repo setup; pqcrypto KAT/CI must still be green |
| **JIT vs AOT variance table** | Systematic same-workload comparison across JIT and AOT builds, documenting the SIMD intrinsification gap. | Requires running both build modes on the same host (procedural) |
| **Memory / allocation profiling** | Heap allocations per NTT/basedmul op; relevant for GC pressure on secret polys. | Pure Dart has no stable allocation-counting API; would need `dart:developer` or package-level instrumentation |

Done (no blocker, already implemented):

| Benchmark | Location |
|-----------|----------|
| Barrett vs `%` microbench | `test/benchmarks/reduce_benchmarks.dart` (`reduceBarrett` vs `reducePercent`) |
| PolyVec / PolyMat ops | `test/benchmarks/polyvec_benchmarks.dart` (construct, clone, indexing, at/setAt, forwardVec) |
| Schoolbook oracle timing | `test/benchmarks/schoolbook_benchmarks.dart` (toy rings n=4/8/16 + FIPS profiles) |
| Montgomery vs Barrett pipeline | `test/benchmarks/pipeline_benchmarks.dart` (plain vs montgomery domain, allocating + in-place) |

### 7.6 Honest limits

- **No claim of speedup over pqcrypto** until a same-host pqcrypto baseline exists for the op being discussed. The manual same-host comparison exists now (`pqcrypto` branch `bench/ntt-side-by-side`, `dart pub get; dart compile exe test/benchmarks/side_by_side.dart` with the pqlattice sibling checkout): bit-identity mlKem 20/20, mlDsa 10/10; measured ns/op rows show pqlattice **slower** on every measured op (mlKem pipeline ~1.94x, mlDsa pipeline ~3.10x slower). Catalogues that gap per op; do not soften or invert it in docs.
- **No SIMD speed claim** until `SimdCapability.isLikelyBeneficial` is flipped on after AOT parity is recorded.
- **No JIT-vs-AOT speedup claims** — only variance documentation.
- **No cross-machine regression thresholds** — same machine only.

---

## 9. Agent checklist

```text
[ ] No speed claim without AOT number attached
[ ] Parity tests green for the kernel measured
[ ] KernelMode and profile stated
[ ] No claim of guaranteed CT or portable SIMD speedup
[ ] Every benchmark row carries full context (sdk, os, cpu, buildMode, profile, gitSha)
[ ] Benchmarks run as nightly job, not as merge gate

# Contributing

Last updated: 2026-10-27

Thank you for interest in `pqlattice`. This package is **pure-Dart lattice
math** for post-quantum work. Please read the binding rules before sending
changes.

## License

**MIT** — see [LICENSE](LICENSE). Contributions are accepted under the same
license.

## Required reading

1. [AGENTS.md](AGENTS.md) — coding and safety rules  
2. [doc/CLAIM_BOUNDARY.md](doc/CLAIM_BOUNDARY.md) — what we may claim  
3. [doc/INTEROP_AND_FIPS_RULE.md](doc/INTEROP_AND_FIPS_RULE.md) — interop lock  
4. [doc/TESTING.md](doc/TESTING.md) — oracle hierarchy and merge gates  
5. [doc/ROADMAP.md](doc/ROADMAP.md) — scope and non-goals  

## Development

```bash
dart pub get
dart analyze
dart test
```

AOT bench (optional):

```bash
dart compile exe tool/bench/ntt_bench.dart -o /tmp/pqlattice_ntt_bench
/tmp/pqlattice_ntt_bench
```

## Pull requests

- Keep PRs focused; map features to a [ROADMAP](doc/ROADMAP.md) milestone.
- Math changes need tests (see TESTING merge gates).
- Do not add `dart:ffi` on the default path.
- Do not move FO / sampling / full scheme KATs into this repo.
- Update CHANGELOG for user-visible behavior.
- No “FIPS validated” or portable constant-time guarantees in docs.

## Upstream Dart SIMD

Track adoption via [doc/SDK_SIMD_TRACKING.md](doc/SDK_SIMD_TRACKING.md). Do not
invent `Int32x4` APIs the SDK does not provide.

## Conduct

Be precise, evidence-based, and respectful. Security-relevant math bugs:
open an issue with a minimal failing case when possible.

/// Exhaustive residue certification for the FN-DSA k=27 single-guard chain.
///
/// Asserts that the exact shipped production chain `NttEngine.fnDsaReduceK27`
/// returns the canonical non-negative residue for EVERY product a*b with
/// a, b in [0, 12289) — 151,019,521 cases, feasible per the audit record
/// (E17). A single expect fires after the sweep so matcher overhead never
/// sits inside the hot loops. This complements the end-to-end engine parity
/// checks: here the shipped reduce itself is certified against `%` truth.
library;

import 'package:pqlattice/src/ntt/ntt_engine.dart';
import 'package:test/test.dart';

void main() {
  const q = 12289;

  test('k=27 single-guard reduce matches % for all 12289^2 products', () {
    final reduce = NttEngine.fnDsaReduceK27;
    var bad = -1;
    for (var a = 0; a < q; a++) {
      for (var b = 0; b < q; b++) {
        final prod = a * b;
        if (reduce(prod) != prod % q) {
          bad = prod;
          break;
        }
      }
      if (bad >= 0) break;
    }
    expect(
      bad,
      -1,
      reason:
          'first mismatching product a*b (-1 means none of the '
          '151,019,521 cases failed)',
    );
  });
}

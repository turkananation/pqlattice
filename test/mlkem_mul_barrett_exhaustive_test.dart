import 'package:pqlattice/src/ntt/ntt_reduce.dart';
import 'package:test/test.dart';

/// Every ML-KEM product `a * b` with `a, b` in `[0, 3329)` through the
/// shipped branchless Barrett multiply.
void main() {
  const q = 3329;

  test('mlKemMulBarrett matches % for all 3329^2 products', () {
    var bad = -1;
    for (var a = 0; a < q; a++) {
      for (var b = 0; b < q; b++) {
        final prod = a * b;
        if (mlKemMulBarrett(a, b) != prod % q) {
          bad = prod;
          break;
        }
      }
      if (bad >= 0) break;
    }
    expect(bad, -1, reason: 'first mismatching product, or -1');
  });
}

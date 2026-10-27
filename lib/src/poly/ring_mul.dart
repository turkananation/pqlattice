import '../mod/mod_q.dart';
import '../ring/ring_params.dart';
import 'poly.dart';

/// Schoolbook and related products in \(\mathbb{Z}_q[x]/(x^n + 1)\)
/// (negacyclic convolution for the usual ML-KEM-style quotient).
///
/// Use as a **correctness oracle** for NTT-based multiplication. Not intended
/// as the hot path once [NttEngine] + [Basemul] are implemented.
final class RingMul {
  RingMul._();

  /// Negacyclic schoolbook product \(c = a \cdot b \bmod (x^n + 1, q)\).
  ///
  /// For each pair \((i,j)\): add \(a_i b_j\) into \(c_{i+j}\) if \(i+j < n\),
  /// else subtract \(a_i b_j\) from \(c_{i+j-n}\) (sign from \(x^n \equiv -1\)).
  static Poly schoolbookNegacyclic(Poly a, Poly b, RingParams ring) {
    if (a.n != ring.n || b.n != ring.n || a.q != ring.q || b.q != ring.q) {
      throw ArgumentError('ring mismatch');
    }
    final n = ring.n;
    final q = ring.q;
    final c = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final prod = ModQ.mul(a.coeffs[i], b.coeffs[j], q);
        final k = i + j;
        if (k < n) {
          c[k] = ModQ.add(c[k], prod, q);
        } else {
          // x^n ≡ -1
          c[k - n] = ModQ.sub(c[k - n], prod, q);
        }
      }
    }
    return Poly.fromCoeffs(ring, c);
  }
}

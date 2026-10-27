import '../mod/coeff.dart';
import '../ring/ring_params.dart';

/// Dense polynomial with [RingParams.n] coefficients in \(\mathbb{Z}_q\).
///
/// **Storage:** by default a contiguous typed buffer from [CoeffBuffer]
/// ([Int16List] for ML-KEM / FN-DSA, [Int32List] for ML-DSA) so acceleration
/// and future SIMD see packed lanes. Indexing is still plain `coeffs[i]` as
/// [int] (see [Coeff]).
///
/// Callers that need secret zeroization should clear [coeffs] via `zeroize`
/// (or equivalent) after use — this type does not own secure lifetime policy.
final class Poly {
  /// Ring this polynomial is interpreted over.
  final RingParams ring;

  /// Length-[n] coefficient vector; mutable for in-place NTT.
  ///
  /// Prefer buffers from [CoeffBuffer.zeros] / [Poly.zero] (typed data).
  final List<int> coeffs;

  /// Lane width used when this poly was allocated (best-effort; plain
  /// [List] from [fromCoeffs] may be growable and non-typed).
  final CoeffWidth width;

  Poly._(this.ring, this.coeffs, this.width);

  /// Zero polynomial with **accelerated** packed storage for [ring].
  factory Poly.zero(RingParams ring, {CoeffWidth? width}) {
    final w = width ?? CoeffLayout.widthFor(ring);
    return Poly._(ring, CoeffBuffer.zeros(ring, width: w), w);
  }

  /// Copies [values] into packed storage for [ring].
  factory Poly.fromCoeffs(
    RingParams ring,
    List<int> values, {
    CoeffWidth? width,
  }) {
    final w = width ?? CoeffLayout.widthFor(ring);
    return Poly._(ring, CoeffBuffer.fromList(ring, values, width: w), w);
  }

  /// Wraps an existing buffer without copying (length must be [ring.n]).
  factory Poly.view(RingParams ring, List<int> coeffs, {CoeffWidth? width}) {
    if (coeffs.length != ring.n) {
      throw ArgumentError(
        'expected ${ring.n} coefficients, got ${coeffs.length}',
      );
    }
    final w =
        width ??
        (CoeffBuffer.isTyped(coeffs)
            ? CoeffLayout.widthFor(ring)
            : CoeffLayout.widthFor(ring));
    return Poly._(ring, coeffs, w);
  }

  int get n => ring.n;
  int get q => ring.q;

  /// Whether [coeffs] is contiguous typed data.
  bool get isPacked => CoeffBuffer.isTyped(coeffs);

  Poly clone() => Poly.fromCoeffs(ring, coeffs, width: width);
}

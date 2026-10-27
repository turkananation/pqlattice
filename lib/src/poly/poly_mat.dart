import '../ring/ring_params.dart';
import 'poly.dart';
import 'poly_vec.dart';

/// Row-major matrix of polynomials (e.g. public matrix \(\mathbf{A}\) in
/// module-LWE sketches).
///
/// Scaffold: storage only. Multiply routines can be added as static helpers
/// once [Basemul] / [NttEngine] are real.
final class PolyMat {
  final RingParams ring;
  final int rows;
  final int cols;

  /// Length `rows * cols`, row-major.
  final List<Poly> entries;

  PolyMat._(this.ring, this.rows, this.cols, this.entries);

  factory PolyMat.zero(RingParams ring, int rows, int cols) {
    if (rows < 0 || cols < 0) {
      throw ArgumentError('rows/cols must be non-negative');
    }
    final n = rows * cols;
    return PolyMat._(
      ring,
      rows,
      cols,
      List<Poly>.generate(n, (_) => Poly.zero(ring)),
    );
  }

  Poly at(int r, int c) {
    _check(r, c);
    return entries[r * cols + c];
  }

  void setAt(int r, int c, Poly p) {
    _check(r, c);
    if (p.n != ring.n || p.q != ring.q) {
      throw ArgumentError('poly ring mismatch');
    }
    entries[r * cols + c] = p;
  }

  /// Placeholder for \(\mathbf{A} \cdot \mathbf{v}\) in NTT domain.
  ///
  /// TODO(Path B): implement using [NttEngine] + [Basemul].
  PolyVec mulVecNttPlaceholder(PolyVec v) {
    if (v.length != cols) {
      throw ArgumentError('dimension mismatch');
    }
    throw UnimplementedError(
      'PolyMat.mulVecNttPlaceholder — implement after scalar NTT/basemul',
    );
  }

  void _check(int r, int c) {
    if (r < 0 || r >= rows || c < 0 || c >= cols) {
      throw RangeError('($r,$c) out of range for ${rows}x$cols');
    }
  }
}

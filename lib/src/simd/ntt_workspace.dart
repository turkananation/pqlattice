import 'dart:typed_data';

/// Scratch lanes for staged NTT kernels, indexed both as scalars and as
/// 4-lane `Int32x4` vectors over the **same** memory.
///
/// The vector view is allocated first (`Int32x4List`), so the backing store is
/// 16-byte aligned by construction and [vectors] can never fault on an
/// unaligned view. [lanes] is the same buffer seen as plain `int32`.
///
/// Allocation only — one workspace per transform (or one shared across a
/// `PolyVec`). Native VM allocation is ~150 ns at n = 256, negligible against
/// the ~10–25 µs kernel.
final class NttWorkspace {
  /// Scalar view over the same bytes as [vectors].
  final Int32List lanes;

  /// 4-lane view over the same bytes as [lanes].
  final Int32x4List vectors;

  NttWorkspace._(this.lanes, this.vectors);

  /// Allocates [n] `int32` lanes ([n] must be a multiple of 4).
  factory NttWorkspace(int n) {
    if (n <= 0 || n % 4 != 0) {
      throw ArgumentError.value(n, 'n', 'must be a positive multiple of 4');
    }
    final vec = Int32x4List(n >> 2);
    return NttWorkspace._(vec.buffer.asInt32List(0, n), vec);
  }
}
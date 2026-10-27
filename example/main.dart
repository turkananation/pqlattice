// ignore_for_file: avoid_print

import 'package:pqlattice/pqlattice.dart';

/// Minimal usage of the lattice math layer (not a KEM or signature scheme).
void main() {
  print('pqlattice example — ring arithmetic only');
  print('Not a FIPS 140 module; not a full ML-KEM implementation.');

  final ring = RingParams.mlKem;
  print('Ring: $ring');

  // Constant polynomials a(x)=3, b(x)=5 → product c(x)=15.
  final a = Poly.zero(ring);
  final b = Poly.zero(ring);
  a.coeffs[0] = 3;
  b.coeffs[0] = 5;

  final engine = NttEngine(ring); // KernelMode.accelerated by default
  final aHat = engine.forward(a);
  final bHat = engine.forward(b);
  // ML-KEM uses paired basemul in the NTT domain (FIPS 203 MultiplyNTTs).
  final cHat = Basemul.mlKemPairs(aHat, bHat, ring);
  final c = engine.inverse(cHat);

  print('NTT-domain product coeff[0] = ${c.coeffs[0]} (expect 15)');

  final school = RingMul.schoolbookNegacyclic(a, b, ring);
  print('Schoolbook coeff[0]         = ${school.coeffs[0]} (expect 15)');
  print('KernelMode default          = ${LatticeKernels.defaultMode}');
}

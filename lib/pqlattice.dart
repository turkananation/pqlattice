/// Pure-Dart lattice and polynomial arithmetic for post-quantum cryptography.
///
/// Provides modular reduction (Barrett by default when parameters are ready,
/// Montgomery domain helpers), dense polynomials and poly-vectors, forward and
/// inverse NTT for ML-KEM, ML-DSA, and FN-DSA integer rings, basemul (including
/// ML-KEM pair products), a schoolbook negacyclic oracle, and SIMD-shaped
/// kernels with scalar parity tests.
///
/// **Acceleration is on by default** ([KernelMode.accelerated]).
///
/// **Claim boundary:** this is a mathematics layer only. It is not a FIPS 140
/// module and not a complete ML-KEM, ML-DSA, or FN-DSA implementation. Scheme
/// logic, sampling, and KATs belong in `pqcrypto`. See `doc/CLAIM_BOUNDARY.md`,
/// `doc/INTEROP_AND_FIPS_RULE.md`, and `doc/API.md`.
library;

export 'src/api/kernel_mode.dart' show KernelMode, resolveKernelMode;
export 'src/api/lattice_kernels.dart' show LatticeKernels;
export 'src/ring/ring_params.dart' show RingParams;
export 'src/mod/coeff.dart'
    show Coeff, CoeffList, CoeffWidth, CoeffLayout, CoeffBuffer;
export 'src/mod/mod_q.dart' show ModQ;
export 'src/mod/barrett_params.dart' show BarrettParams;
export 'src/mod/montgomery_params.dart' show MontgomeryParams;
export 'src/poly/poly.dart' show Poly;
export 'src/poly/poly_ops.dart' show PolyOps;
export 'src/poly/poly_vec.dart' show PolyVec;
export 'src/poly/poly_mat.dart' show PolyMat;
export 'src/poly/ring_mul.dart' show RingMul;
export 'src/ntt/ntt_params.dart' show NttParams;
export 'src/ntt/ntt_engine.dart' show NttEngine;
export 'src/ntt/basemul.dart' show Basemul;

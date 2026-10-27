import '../ring/ring_params.dart';
import 'mlkem_tables.dart';
import 'mldsa_tables.dart';
import 'fndsa_tables.dart';

final class NttParams {
  final RingParams ring;
  final List<int> zetas;
  final List<int> gammas;
  final int invNScale;

  const NttParams({
    required this.ring,
    required this.zetas,
    this.gammas = const <int>[],
    this.invNScale = 1,
  });

  factory NttParams.mlKem() => NttParams(
    ring: RingParams.mlKem,
    zetas: mlKemZetas,
    gammas: mlKemGammas,
    invNScale: mlKemInv128,
  );

  factory NttParams.mlDsa() => NttParams(
    ring: RingParams.mlDsa,
    zetas: mlDsaZetas,
    invNScale: mlDsaInv256,
  );

  factory NttParams.fnDsa512() => NttParams(
    ring: RingParams.fnDsa512,
    zetas: fnDsa512Zetas,
    invNScale: fnDsa512InvN,
  );

  factory NttParams.fnDsa1024() => NttParams(
    ring: RingParams.fnDsa1024,
    zetas: fnDsa1024Zetas,
    invNScale: fnDsa1024InvN,
  );

  /// Selects table set from a known [RingParams] preset.
  ///
  /// Throws [ArgumentError] for rings without a shipped NTT table set.
  factory NttParams.forRing(RingParams ring) {
    if (ring.q == 3329 && ring.n == 256) return NttParams.mlKem();
    if (ring.q == 8380417 && ring.n == 256) return NttParams.mlDsa();
    if (ring.q == 12289 && ring.n == 512) return NttParams.fnDsa512();
    if (ring.q == 12289 && ring.n == 1024) return NttParams.fnDsa1024();
    throw ArgumentError(
      'no NTT tables for ring ${ring.name} (q=${ring.q}, n=${ring.n})',
    );
  }

  /// True when a non-empty twiddle table is present.
  bool get hasZetas => zetas.isNotEmpty;
}

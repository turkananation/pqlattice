import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  test('named ring presets', () {
    expect(RingParams.mlKem.q, 3329);
    expect(RingParams.mlKem.n, 256);
    expect(RingParams.mlDsa.q, 8380417);
    expect(RingParams.fnDsa512.q, 12289);
    expect(RingParams.fnDsa512.n, 512);
    expect(RingParams.fnDsa1024.n, 1024);
    expect(RingParams.fnDsa512.isFnDsaIntegerRing, isTrue);
    expect(RingParams.mlKem.isFnDsaIntegerRing, isFalse);
  });

  test('NttParams factories bind correct rings', () {
    expect(NttParams.fnDsa512().ring.n, 512);
    expect(NttParams.fnDsa1024().ring.q, 12289);
    expect(NttParams.mlDsa().ring.name, 'ml-dsa');
  });
}

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

/// Structural checks aligned with `doc/TABLE_PROVENANCE.md`.
void main() {
  test('ML-KEM tables lengths and invN', () {
    final p = NttParams.mlKem();
    expect(p.zetas.length, 128);
    expect(p.gammas.length, 128);
    expect(p.zetas.first, 1);
    expect((p.invNScale * 128) % 3329, 1);
  });

  test('ML-DSA tables lengths and invN', () {
    final p = NttParams.mlDsa();
    expect(p.zetas.length, 256);
    expect((p.invNScale * 256) % 8380417, 1);
  });

  test('FN-DSA-512 tables lengths and invN', () {
    final p = NttParams.fnDsa512();
    expect(p.zetas.length, 512);
    expect(p.zetas.first, 1);
    expect((p.invNScale * 512) % 12289, 1);
  });

  test('FN-DSA-1024 tables lengths and invN', () {
    final p = NttParams.fnDsa1024();
    expect(p.zetas.length, 1024);
    expect(p.zetas.first, 1);
    expect((p.invNScale * 1024) % 12289, 1);
  });
}

import 'package:bio_flutter/bio_flutter.dart';
import 'package:biocentral/plugins/protein_engineering/domain/structure_sequence.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

const _fixture = '''
data_TEST
loop_
_atom_site.group_PDB
_atom_site.id
_atom_site.type_symbol
_atom_site.label_atom_id
_atom_site.label_asym_id
_atom_site.label_entity_id
_atom_site.auth_asym_id
_atom_site.auth_seq_id
_atom_site.label_seq_id
_atom_site.label_comp_id
_atom_site.Cartn_x
_atom_site.Cartn_y
_atom_site.Cartn_z
ATOM 1 C CA A 1 A 1 1 ALA 1.0 1.0 1.0
ATOM 2 C CA A 1 A 2 2 GLY 2.0 2.0 2.0
ATOM 3 C CA A 1 A 3 3 VAL 3.0 3.0 3.0
loop_
_entity.id
_entity.type
1 polymer
loop_
_entity_poly.entity_id
_entity_poly.type
1 polypeptide(L)
''';

void main() {
  test('extractChainSequence orders residues by labelSeqId and maps three-letter codes', () async {
    final result = await MmcifParser.parse(_fixture);
    final chainSequence = extractChainSequence(result.structure.chains.single);
    expect(chainSequence.sequence, 'AGV');
  });

  test('matchWildtypeStructure finds the chain matching the wildtype sequence', () async {
    final result = await MmcifParser.parse(_fixture);
    final match = matchWildtypeStructure(result.structure, 'AGV');
    expect(match, isNotNull);
    expect(match!.chainSequence.sequence, 'AGV');
  });

  test('matchWildtypeStructure returns null when no chain matches', () async {
    final result = await MmcifParser.parse(_fixture);
    expect(matchWildtypeStructure(result.structure, 'AAAA'), isNull);
  });

  test('highlightsForCandidate flags only the differing residue, by wildtype position', () async {
    final result = await MmcifParser.parse(_fixture);
    final match = matchWildtypeStructure(result.structure, 'AGV')!;
    const color = Color(0xFF8E24AA);
    final highlights = highlightsForCandidate(
      match: match,
      wildtypeSequence: 'AGV',
      candidateSequence: 'AVV', // G2V
      color: color,
    );
    expect(highlights, hasLength(1));
    expect(highlights[match.residueKeyForPosition(2)], color);
  });
}

import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/bloc/biocentral_command.dart';
import 'package:biocentral/sdk/domain/biocentral_project_repository.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _mismatchingFixture = '''
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
loop_
_entity.id
_entity.type
1 polymer
loop_
_entity_poly.entity_id
_entity_poly.type
1 polypeptide(L)
''';

EngineeringCampaign _buildCampaign({String? wildtypeStructureMmcif}) {
  return EngineeringCampaign(
    config: ActiveLearningEngineeringCampaignConfig((b) => b
      ..name = 'Test-Campaign'
      ..embedderName = 'facebook/esm2_t33_650M_UR50D'
      ..modelType = ActiveLearningModelType.GAUSSIAN_PROCESS
      ..optimizationMode = ActiveLearningOptimizationMode.MAXIMIZE
      ..seed = 42
      ..wildtypeSequence = 'AGV'),
    wildtypeId: 'wt',
    wildtypeSequence: 'AGV',
    measurementName: 'activity',
    measurementUnit: '%',
    wildtypeStructureMmcif: wildtypeStructureMmcif,
  );
}

void main() {
  test('rejects a structure whose sequence does not match the wildtype, keeping the existing one', () async {
    final campaign = _buildCampaign(wildtypeStructureMmcif: 'existing-structure-content');
    final command = UploadWildtypeStructureCommand(
      engineeringRepository: EngineeringRepository(BiocentralProjectRepository('')),
      campaign: campaign,
      mmcifContent: _mismatchingFixture, // sequence AG, not AGV
    );

    final log = await command.execute().last;

    expect(log.commandStatus, BiocentralCommandStatus.errored);
    expect(campaign.wildtypeStructureMmcif, 'existing-structure-content');
  });
}

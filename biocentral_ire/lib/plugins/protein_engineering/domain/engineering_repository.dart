import 'dart:convert';

import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/domain/biocentral_project_repository.dart';
import 'package:biocentral/sdk/domain/biocentral_repository_auto_saver.dart';
import 'package:biocentral/sdk/domain/streamable_database.dart';

/// Repository for managing protein engineering campaigns.
class EngineeringRepository with AutoSaving, StreamableDatabase<List<EngineeringCampaign>> {
  @override
  late final BiocentralRepositoryAutoSaver autoSaver;

  final Map<String, EngineeringCampaign> _campaigns = {};

  EngineeringRepository(BiocentralProjectRepository projectRepository) {
    autoSaver = BiocentralRepositoryAutoSaver(
      projectRepository: projectRepository,
      fileName: 'engineering_results.json',
      fileType: EngineeringCampaign,
      saveFunctionString: saveDBInfo,
    );
  }

  void addNewCampaign(EngineeringCampaign campaign) {
    final internalName = campaign.internalName();
    _campaigns[internalName] = campaign;
    autosave();
    updateStream();
  }

  void addNewCampaigns(List<EngineeringCampaign> campaigns) {
    for (final campaign in campaigns) {
      final internalName = campaign.internalName();
      _campaigns[internalName] = campaign;
    }
    autosave();
    updateStream();
  }

  void updateCampaign(EngineeringCampaign campaign) {
    addNewCampaign(campaign);
  }

  Map<String, dynamic> serialize() => {'campaigns': _campaigns.values.map((campaign) => campaign.serialize()).toList()};

  Future<String> saveDBInfo() async {
    final jsonMap = serialize();
    return jsonEncode(jsonMap);
  }

  List<EngineeringCampaign> campaignsToList() => List.from(_campaigns.values);

  @override
  List<EngineeringCampaign> toStreamable() => campaignsToList();
}

import 'dart:convert';

import 'package:bio_flutter/bio_flutter.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/domain/structure_sequence.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/biocentral_sdk.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:cross_file/cross_file.dart';

/// Substitutions are relative to the campaign's wildtype.
class SeedMeasurement {
  final List<Substitution> substitutions;
  final double? fitness;

  SeedMeasurement({required this.substitutions, required this.fitness});
}

final class NewEngineeringCampaignCommand extends BiocentralCommand<EngineeringCampaign> {
  final EngineeringRepository _engineeringRepository;
  final ActiveLearningEngineeringCampaignConfig _campaignConfig;
  final String _wildtypeId;
  final String _wildtypeSequence;
  final String _measurementName;
  final String _measurementUnit;
  final double? _wildtypeFitness;
  final List<SeedMeasurement> _seedMeasurements;

  NewEngineeringCampaignCommand({
    required EngineeringRepository engineeringRepository,
    required ActiveLearningEngineeringCampaignConfig campaignConfig,
    required String wildtypeId,
    required String wildtypeSequence,
    required String measurementName,
    required String measurementUnit,
    double? wildtypeFitness,
    List<SeedMeasurement> seedMeasurements = const [],
  })  : _engineeringRepository = engineeringRepository,
        _campaignConfig = campaignConfig,
        _wildtypeId = wildtypeId,
        _wildtypeSequence = wildtypeSequence,
        _measurementName = measurementName,
        _measurementUnit = measurementUnit,
        _wildtypeFitness = wildtypeFitness,
        _seedMeasurements = seedMeasurements;

  @override
  Stream<BiocentralCommandLog<EngineeringCampaign>> execute() async* {
    BiocentralCommandLog<EngineeringCampaign> log = initLog();
    yield log = log.logInfo(information: 'Creating campaign "${_campaignConfig.name}"..');

    final campaign = EngineeringCampaign(
      config: _campaignConfig,
      wildtypeId: _wildtypeId,
      wildtypeSequence: _wildtypeSequence,
      measurementName: _measurementName,
      measurementUnit: _measurementUnit,
      wildtypeFitness: _wildtypeFitness,
    );

    if (_wildtypeFitness != null) {
      campaign.addMeasurement(MeasuredVariant(
        seqId: '${_campaignConfig.name}_wt',
        sequence: _wildtypeSequence,
        parentSequence: _wildtypeSequence,
        substitutions: const [],
        roundFound: 0,
        fitness: _wildtypeFitness,
      ));
    }

    for (final seed in _seedMeasurements) {
      final sequence = applySubstitutions(_wildtypeSequence, seed.substitutions);
      if (sequence == null) {
        continue;
      }
      campaign.addMeasurement(MeasuredVariant(
        seqId: '${_campaignConfig.name}_r0_${formatSubstitutions(seed.substitutions).replaceAll(' + ', '_')}',
        sequence: sequence,
        parentSequence: _wildtypeSequence,
        substitutions: seed.substitutions,
        roundFound: 0,
        fitness: seed.fitness,
      ));
    }

    yield log.finish(
      result: BiocentralCommandResult(campaign, {'campaignName': campaign.config.name}),
      finalProgress: BiocentralCommandProgress(information: 'Campaign created!', current: 1, total: 1),
    );
  }

  @override
  void acceptResult(BiocentralCommandLog? resultLog) {
    final commandResult = resultLog?.result?.result;
    if (commandResult != null && commandResult is EngineeringCampaign) {
      _engineeringRepository.addNewCampaign(commandResult);
    }
  }

  @override
  Map<String, dynamic> getConfigMap() {
    return {
      'campaignName': _campaignConfig.name,
      'wildtypeId': _wildtypeId,
    };
  }

  @override
  String get typeName => 'NewEngineeringCampaignCommand';
}

final class UploadWildtypeStructureCommand extends BiocentralCommand<EngineeringCampaign> {
  final EngineeringRepository _engineeringRepository;
  final EngineeringCampaign _campaign;
  final String _mmcifContent;

  UploadWildtypeStructureCommand({
    required EngineeringRepository engineeringRepository,
    required EngineeringCampaign campaign,
    required String mmcifContent,
  })  : _engineeringRepository = engineeringRepository,
        _campaign = campaign,
        _mmcifContent = mmcifContent;

  @override
  Stream<BiocentralCommandLog<EngineeringCampaign>> execute() async* {
    BiocentralCommandLog<EngineeringCampaign> log = initLog();
    yield log = log.logInfo(information: 'Parsing uploaded structure..');

    final MmcifParseResult parseResult;
    try {
      parseResult = await MmcifParser.parse(_mmcifContent);
    } catch (e) {
      yield log.errored(error: 'Could not parse the structure file: $e');
      return;
    }

    if (parseResult.structure.atoms.isEmpty) {
      yield log.errored(error: 'The structure file has no amino acid chains.');
      return;
    }

    if (matchWildtypeStructure(parseResult.structure, _campaign.wildtypeSequence) == null) {
      yield log.errored(error: "No chain in the uploaded structure matches this campaign's wildtype sequence.");
      return;
    }

    yield log.finish(
      result: BiocentralCommandResult(_campaign, {'campaignName': _campaign.config.name}),
      finalProgress: const BiocentralCommandProgress(
        information: 'Structure matches the wildtype sequence!',
        current: 1,
        total: 1,
      ),
    );
  }

  @override
  void acceptResult(BiocentralCommandLog? resultLog) {
    final commandResult = resultLog?.result?.result;
    if (commandResult != null && commandResult is EngineeringCampaign) {
      commandResult.wildtypeStructureMmcif = _mmcifContent;
      _engineeringRepository.updateCampaign(commandResult);
    }
  }

  @override
  Map<String, dynamic> getConfigMap() {
    return {'campaignName': _campaign.config.name};
  }

  @override
  String get typeName => 'UploadWildtypeStructureCommand';
}

final class RunEngineeringRoundCommand extends BiocentralCommand<ActiveLearningIterationResult> {
  final BiocentralAPIRepository _apiRepository;
  final EngineeringRepository _engineeringRepository;
  final EngineeringCampaign _campaign;
  final ActiveLearningEngineeringIterationConfig _iterationConfig;
  final String _parentSequence;

  RunEngineeringRoundCommand({
    required BiocentralAPIRepository apiRepository,
    required EngineeringRepository engineeringRepository,
    required EngineeringCampaign campaign,
    required ActiveLearningEngineeringIterationConfig iterationConfig,
    required String parentSequence,
  })  : _apiRepository = apiRepository,
        _engineeringRepository = engineeringRepository,
        _campaign = campaign,
        _iterationConfig = iterationConfig,
        _parentSequence = parentSequence;

  @override
  Stream<BiocentralCommandLog<ActiveLearningIterationResult>> execute() async* {
    BiocentralCommandLog<ActiveLearningIterationResult> log = initLog();
    yield log = log.logInfo(
      information: 'Running round ${_iterationConfig.iteration} for campaign ${_campaign.config.name}..',
    );

    final biocentralAPI = _apiRepository.getBiocentralAPI();
    final task = await biocentralAPI.engineeringIteration(
      campaignConfig: _campaign.config,
      iterationConfig: _iterationConfig,
    );

    await for (final (dto, result) in task.run()) {
      if (dto != null) {
        if (dto.status == TaskStatus.RUNNING) {
          final embeddingProgress = dto.embeddingProgress;
          if (embeddingProgress != null) {
            yield log = log.logProgress(
              progress: BiocentralCommandProgress(
                information: 'Encoding variants with the language model..',
                current: embeddingProgress.current,
                total: embeddingProgress.total,
              ),
            );
          } else {
            yield log = log.logInfo(information: 'Running round..');
          }
        }
      } else if (result != null) {
        yield log.finish(
          result: BiocentralCommandResult(result, {'suggestions': result.suggestions.toList()}),
          finalProgress: BiocentralCommandProgress(
            information: 'Round finished!',
            current: _iterationConfig.iteration,
            total: _iterationConfig.iteration,
          ),
        );
        return;
      }
    }

    yield log.errored(error: 'Did not receive a round result!');
  }

  @override
  void acceptResult(BiocentralCommandLog? resultLog) {
    final commandResult = resultLog?.result?.result;
    if (commandResult != null && commandResult is ActiveLearningIterationResult) {
      _campaign.addRound(EngineeringRound(
        sentConfig: _iterationConfig,
        result: commandResult,
        parentSequence: _parentSequence,
        startedAt: resultLog?.metaData.startTime ?? DateTime.now(),
        finishedAt: resultLog?.metaData.endTime,
      ));
      _engineeringRepository.updateCampaign(_campaign);
    }
  }

  @override
  Map<String, dynamic> getConfigMap() {
    return {
      'campaignName': _campaign.config.name,
      'iteration': _iterationConfig.iteration,
    };
  }

  @override
  String get typeName => 'RunEngineeringRoundCommand';
}

final class AddEngineeringMeasurementsCommand extends BiocentralCommand<EngineeringCampaign> {
  final EngineeringRepository _engineeringRepository;
  final EngineeringCampaign _campaign;
  final List<MeasuredVariant> _newMeasurements;

  AddEngineeringMeasurementsCommand({
    required EngineeringRepository engineeringRepository,
    required EngineeringCampaign campaign,
    required List<MeasuredVariant> newMeasurements,
  })  : _engineeringRepository = engineeringRepository,
        _campaign = campaign,
        _newMeasurements = newMeasurements;

  @override
  Stream<BiocentralCommandLog<EngineeringCampaign>> execute() async* {
    BiocentralCommandLog<EngineeringCampaign> log = initLog();
    yield log = log.logInfo(information: 'Adding ${_newMeasurements.length} measurement(s)..');

    yield log.finish(
      result: BiocentralCommandResult(_campaign, {'measurementsAdded': _newMeasurements.length}),
      finalProgress: BiocentralCommandProgress(
        information: 'Measurements saved!',
        current: _newMeasurements.length,
        total: _newMeasurements.length,
      ),
    );
  }

  @override
  void acceptResult(BiocentralCommandLog? resultLog) {
    final commandResult = resultLog?.result?.result;
    if (commandResult != null && commandResult is EngineeringCampaign) {
      for (final variant in _newMeasurements) {
        commandResult.addMeasurement(variant);
      }
      _engineeringRepository.updateCampaign(commandResult);
    }
  }

  @override
  Map<String, dynamic> getConfigMap() {
    return {
      'campaignName': _campaign.config.name,
      'measurementsAdded': _newMeasurements.length,
    };
  }

  @override
  String get typeName => 'AddEngineeringMeasurementsCommand';
}

final class ExportEngineeringCampaignCommand extends BiocentralCommand<String> {
  final BiocentralProjectRepository _projectRepository;
  final EngineeringCampaign _campaign;
  final String _filePath;

  ExportEngineeringCampaignCommand({
    required BiocentralProjectRepository projectRepository,
    required EngineeringCampaign campaign,
    required String filePath,
  })  : _projectRepository = projectRepository,
        _campaign = campaign,
        _filePath = filePath;

  @override
  Stream<BiocentralCommandLog<String>> execute() async* {
    BiocentralCommandLog<String> log = initLog();
    yield log = log.logInfo(information: 'Exporting campaign "${_campaign.config.name}"...');

    final xFile = XFile(_filePath);
    final fileName = xFile.name;
    final dirPath = _filePath.substring(0, _filePath.length - fileName.length - 1);

    final saveEither = await _projectRepository.handleExternalSave(
      fileName: fileName,
      contentFunction: () async => jsonEncode({
        'campaigns': [_campaign.serialize()]
      }),
      dirPath: dirPath,
    );
    yield saveEither.match(
      (l) => log.errored(error: l.message),
      (r) => log.finish(
        result: BiocentralCommandResult(r ?? '', {'filePath': r ?? ''}),
        finalProgress: BiocentralCommandProgress(
          information: 'Campaign "${_campaign.config.name}" exported to $r!',
          current: 1,
          total: 1,
        ),
      ),
    );
  }

  @override
  void acceptResult(BiocentralCommandLog? resultLog) {
    // Export has no side effects on the repository
  }

  @override
  Map<String, dynamic> getConfigMap() {
    return {
      'campaignName': _campaign.config.name,
      'filePath': _filePath,
    };
  }

  @override
  String get typeName => 'ExportEngineeringCampaignCommand';
}

final class LoadEngineeringCampaignCommand extends BiocentralCommand<List<EngineeringCampaign>> {
  final BiocentralProjectRepository _projectRepository;
  final EngineeringRepository _engineeringRepository;

  final XFile _campaignFile;
  final DatabaseImportMode _importMode;

  LoadEngineeringCampaignCommand({
    required BiocentralProjectRepository projectRepository,
    required EngineeringRepository engineeringRepository,
    required XFile campaignFile,
    required DatabaseImportMode importMode,
  })  : _projectRepository = projectRepository,
        _engineeringRepository = engineeringRepository,
        _campaignFile = campaignFile,
        _importMode = importMode;

  @override
  Stream<BiocentralCommandLog<List<EngineeringCampaign>>> execute() async* {
    BiocentralCommandLog<List<EngineeringCampaign>> log = initLog();
    yield log = log.logInfo(information: 'Loading protein engineering campaigns from file..');

    final LoadedFileData? campaignFileData =
        (await _projectRepository.handleLoad(xFile: _campaignFile, ignoreIfNoFile: true)).getOrElse((l) => null);
    if (campaignFileData == null || campaignFileData.content.isEmpty) {
      yield log.errored(error: 'Could not read campaign file!');
      return;
    }
    final campaignJson = jsonDecode(campaignFileData.content) as Map<String, dynamic>;
    final campaignMaps = campaignJson['campaigns'] as List<dynamic>? ?? [];
    final campaigns = campaignMaps
        .map((campaignMap) => EngineeringCampaign.deserialize(campaignMap as Map<String, dynamic>))
        .whereType<EngineeringCampaign>()
        .toList();
    yield log.finish(
      result: BiocentralCommandResult(campaigns, campaignJson),
      finalProgress: BiocentralCommandProgress(
        information: 'Finished loading campaigns!',
        current: campaigns.length,
        total: campaigns.length,
      ),
    );
  }

  @override
  void acceptResult(BiocentralCommandLog? resultLog) {
    final commandResult = resultLog?.result?.result;
    if (commandResult != null && commandResult is List<EngineeringCampaign>) {
      _engineeringRepository.addNewCampaigns(commandResult);
    }
  }

  @override
  Map<String, dynamic> getConfigMap() {
    return {
      'campaignFile': _campaignFile.name,
      'importMode': _importMode.name,
    };
  }

  @override
  String get typeName => 'LoadEngineeringCampaignCommand';
}

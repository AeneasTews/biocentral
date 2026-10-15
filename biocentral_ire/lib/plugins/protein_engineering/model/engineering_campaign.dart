import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral_api/biocentral_api.dart';

class EngineeringCampaign {
  ActiveLearningEngineeringCampaignConfig config;
  String wildtypeId;
  String wildtypeSequence;
  double? wildtypeFitness;
  String measurementName;
  String measurementUnit; // Display metadata, not sent to the server.

  /// Keyed by sequence because mutation descriptors are relative to each round's parent.
  Map<String, MeasuredVariant> measurements;

  List<EngineeringRound> rounds;

  /// Raw mmCIF text of a structure whose sequence matches [wildtypeSequence] exactly.
  /// Null until a matching structure has been uploaded.
  String? wildtypeStructureMmcif;

  EngineeringCampaign({
    required this.config,
    required this.wildtypeId,
    required this.wildtypeSequence,
    required this.measurementName,
    required this.measurementUnit,
    this.wildtypeFitness,
    Map<String, MeasuredVariant>? measurements,
    List<EngineeringRound>? rounds,
    this.wildtypeStructureMmcif,
  })  : measurements = measurements ?? {},
        rounds = rounds ?? [];

  String internalName() {
    return config.name + wildtypeId + config.hashCode.toString();
  }

  void addRound(EngineeringRound round) {
    rounds.add(round);
  }

  void addMeasurement(MeasuredVariant variant) {
    measurements[variant.sequence] = variant;
  }

  factory EngineeringCampaign.deserialize(Map<String, dynamic> jsonMap) {
    final measurementsJson = jsonMap['measurements'] as List<dynamic>? ?? [];
    final roundsJson = jsonMap['rounds'] as List<dynamic>? ?? [];
    return EngineeringCampaign(
      config: EngineeringCampaignConfigSerial.deserialize(jsonMap['config'] as Map<String, dynamic>),
      wildtypeId: jsonMap['wildtypeId'] as String,
      wildtypeSequence: jsonMap['wildtypeSequence'] as String,
      wildtypeFitness: (jsonMap['wildtypeFitness'] as num?)?.toDouble(),
      measurementName: jsonMap['measurementName'] as String,
      measurementUnit: jsonMap['measurementUnit'] as String,
      measurements: {
        for (final entry in measurementsJson)
          (entry as Map<String, dynamic>)['sequence'] as String: MeasuredVariant.deserialize(entry),
      },
      rounds: roundsJson.map((entry) => EngineeringRound.deserialize(entry as Map<String, dynamic>)).toList(),
      wildtypeStructureMmcif: jsonMap['wildtypeStructureMmcif'] as String?,
    );
  }

  Map<String, dynamic> serialize() {
    return {
      'config': config.serialize(),
      'wildtypeId': wildtypeId,
      'wildtypeSequence': wildtypeSequence,
      'wildtypeFitness': wildtypeFitness,
      'measurementName': measurementName,
      'measurementUnit': measurementUnit,
      'measurements': measurements.values.map((variant) => variant.serialize()).toList(),
      'rounds': rounds.map((round) => round.serialize()).toList(),
      'wildtypeStructureMmcif': wildtypeStructureMmcif,
    };
  }
}

class EngineeringRound {
  ActiveLearningEngineeringIterationConfig sentConfig;
  ActiveLearningIterationResult result; // full library for this round, may be empty
  String parentSequence;
  DateTime startedAt;
  DateTime? finishedAt;

  EngineeringRound({
    required this.sentConfig,
    required this.result,
    required this.parentSequence,
    required this.startedAt,
    this.finishedAt,
  });

  factory EngineeringRound.deserialize(Map<String, dynamic> jsonMap) {
    return EngineeringRound(
      sentConfig: EngineeringIterationConfigSerial.deserialize(jsonMap['sentConfig'] as Map<String, dynamic>),
      result: ALIterationResultSerial.deserialize(jsonMap['result'] as Map<String, dynamic>),
      parentSequence: jsonMap['parentSequence'] as String,
      startedAt: DateTime.parse(jsonMap['startedAt'] as String),
      finishedAt: jsonMap['finishedAt'] != null ? DateTime.parse(jsonMap['finishedAt'] as String) : null,
    );
  }

  Map<String, dynamic> serialize() {
    return {
      'sentConfig': sentConfig.serialize(),
      'result': result.serialize(),
      'parentSequence': parentSequence,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt?.toIso8601String(),
    };
  }
}

class MeasuredVariant {
  String seqId;
  String sequence;
  String parentSequence;
  List<Substitution> substitutions; // parent-relative
  double? fitness; // null = did not express, distinct from an untested variant
  int roundFound; // 0 = user-seeded before the first round

  MeasuredVariant({
    required this.seqId,
    required this.sequence,
    required this.parentSequence,
    required this.substitutions,
    required this.roundFound,
    this.fitness,
  });

  bool get didNotExpress => fitness == null;

  factory MeasuredVariant.deserialize(Map<String, dynamic> jsonMap) {
    final substitutionsJson = jsonMap['substitutions'] as List<dynamic>? ?? [];
    return MeasuredVariant(
      seqId: jsonMap['seqId'] as String,
      sequence: jsonMap['sequence'] as String,
      parentSequence: jsonMap['parentSequence'] as String,
      substitutions: substitutionsJson
          .map(
            (entry) => Substitution(
              position: (entry as Map<String, dynamic>)['position'] as int,
              from: entry['from'] as String,
              to: entry['to'] as String,
            ),
          )
          .toList(),
      roundFound: jsonMap['roundFound'] as int,
      fitness: (jsonMap['fitness'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> serialize() {
    return {
      'seqId': seqId,
      'sequence': sequence,
      'parentSequence': parentSequence,
      'substitutions': substitutions
          .map(
            (substitution) => {
              'position': substitution.position,
              'from': substitution.from,
              'to': substitution.to,
            },
          )
          .toList(),
      'roundFound': roundFound,
      'fitness': fitness,
    };
  }
}

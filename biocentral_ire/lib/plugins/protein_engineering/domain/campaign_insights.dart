import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral_api/biocentral_api.dart';

bool _maximizes(EngineeringCampaign campaign) =>
    campaign.config.optimizationMode == ActiveLearningOptimizationMode.MAXIMIZE;

/// The best-measured, expressed variant so far, or null if nothing has been measured.
MeasuredVariant? bestMeasuredVariant(EngineeringCampaign campaign) {
  final measured = campaign.measurements.values.where((variant) => variant.fitness != null).toList();
  if (measured.isEmpty) {
    return null;
  }
  final maximize = _maximizes(campaign);
  measured.sort((a, b) => maximize ? b.fitness!.compareTo(a.fitness!) : a.fitness!.compareTo(b.fitness!));
  return measured.first;
}

/// The best variant's improvement over the wildtype, or null if either is unknown.
double? bestOverWildtype(EngineeringCampaign campaign) {
  final best = bestMeasuredVariant(campaign);
  final wildtypeFitness = campaign.wildtypeFitness;
  if (best == null || wildtypeFitness == null) {
    return null;
  }
  return best.fitness! - wildtypeFitness;
}

/// The best measured value after each round, in round order. Only rounds with a measured
/// improvement are included, so the series may be shorter than the round count.
List<(int round, double value)> bestPerRound(EngineeringCampaign campaign) {
  final maximize = _maximizes(campaign);
  final maxRound =
      campaign.rounds.fold<int>(0, (max, round) => round.sentConfig.iteration > max ? round.sentConfig.iteration : max);
  final series = <(int, double)>[];
  double? best;
  for (var round = 0; round <= maxRound; round++) {
    for (final variant in campaign.measurements.values.where((v) => v.roundFound == round && v.fitness != null)) {
      if (best == null || (maximize ? variant.fitness! > best : variant.fitness! < best)) {
        best = variant.fitness;
      }
    }
    if (best != null) {
      series.add((round, best));
    }
  }
  return series;
}

/// The average absolute difference between a round's predictions and what was actually
/// measured for the same variant, across every round. Null if nothing overlaps yet.
double? meanAbsoluteError(EngineeringCampaign campaign) {
  final errors = <double>[];
  for (final round in campaign.rounds) {
    for (final result in round.result.results) {
      final predicted = double.tryParse(result.prediction);
      if (predicted == null) {
        continue;
      }
      String? sequence;
      try {
        sequence = applySubstitutions(round.parentSequence, parseMutationDescriptor(result.entityId));
      } on UnresolvableVariantException {
        continue;
      }
      final measured = sequence != null ? campaign.measurements[sequence] : null;
      if (measured == null || measured.fitness == null) {
        continue;
      }
      errors.add((measured.fitness! - predicted).abs());
    }
  }
  if (errors.isEmpty) {
    return null;
  }
  return errors.reduce((a, b) => a + b) / errors.length;
}

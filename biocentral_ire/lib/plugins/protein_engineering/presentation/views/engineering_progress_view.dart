import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class EngineeringProgressView extends StatelessWidget {
  final EngineeringCampaign campaign;

  const EngineeringProgressView({required this.campaign, super.key});

  bool get _maximize => campaign.config.optimizationMode == ActiveLearningOptimizationMode.MAXIMIZE;

  MeasuredVariant? get _bestVariant {
    final measured = campaign.measurements.values.where((v) => v.fitness != null).toList();
    if (measured.isEmpty) {
      return null;
    }
    measured.sort((a, b) => _maximize ? b.fitness!.compareTo(a.fitness!) : a.fitness!.compareTo(b.fitness!));
    return measured.first;
  }

  List<FlSpot> get _bestPerRoundSpots {
    final maxRound = campaign.rounds
        .fold<int>(0, (max, round) => round.sentConfig.iteration > max ? round.sentConfig.iteration : max);
    final spots = <FlSpot>[];
    double? best;
    for (var round = 0; round <= maxRound; round++) {
      for (final variant in campaign.measurements.values.where((v) => v.roundFound == round && v.fitness != null)) {
        if (best == null || (_maximize ? variant.fitness! > best : variant.fitness! < best)) {
          best = variant.fitness;
        }
      }
      if (best != null) {
        spots.add(FlSpot(round.toDouble(), best));
      }
    }
    return spots;
  }

  double? get _meanAbsoluteError {
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

  @override
  Widget build(BuildContext context) {
    final best = _bestVariant;
    final measuredCount = campaign.measurements.values.where((v) => v.fitness != null).length;
    final mae = _meanAbsoluteError;
    final spots = _bestPerRoundSpots;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _statTile(
                  'Best variant',
                  best != null ? '${best.fitness}' : '--',
                  best != null
                      ? (best.substitutions.isEmpty ? 'wildtype' : formatSubstitutions(best.substitutions))
                      : null),
              _statTile(
                  'Over wildtype',
                  best != null && campaign.wildtypeFitness != null
                      ? (best.fitness! - campaign.wildtypeFitness!).toStringAsFixed(2)
                      : '--',
                  null),
              _statTile('Rounds', '${campaign.rounds.length}', '$measuredCount measured'),
              _statTile('Typical model error', mae != null ? mae.toStringAsFixed(2) : '--', null),
            ],
          ),
          const SizedBox(height: 24),
          if (spots.length > 1) ...[
            const Text('Best measured value, round by round'),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(spots: spots, isCurved: false, dotData: const FlDotData(show: true)),
                  ],
                ),
              ),
            ),
          ] else
            const Text('Best measured value will chart here once a few rounds are complete.'),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, String? sublabel) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 22)),
          if (sublabel != null) Text(sublabel, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

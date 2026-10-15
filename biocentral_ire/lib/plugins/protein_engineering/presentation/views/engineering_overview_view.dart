import 'package:biocentral/plugins/protein_engineering/domain/campaign_insights.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/commands/run_engineering_round_dialog.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/style/engineering_style.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// The campaign's at-a-glance dashboard: best result, progress chart, and recent rounds.
class EngineeringOverviewView extends StatelessWidget {
  final EngineeringCampaign campaign;
  final ValueChanged<int> onOpenRound;
  final VoidCallback onOpenHistory;

  const EngineeringOverviewView({
    required this.campaign,
    required this.onOpenRound,
    required this.onOpenHistory,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final best = bestMeasuredVariant(campaign);
    final overWildtype = bestOverWildtype(campaign);
    final series = bestPerRound(campaign);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(campaign.config.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Goal — ${campaign.measurementName.isEmpty ? 'maximize fitness' : campaign.measurementName}'
                      '${campaign.measurementUnit.isEmpty ? '' : ' (${campaign.measurementUnit})'}, '
                      '${campaign.config.optimizationMode == ActiveLearningOptimizationMode.MAXIMIZE ? 'higher' : 'lower'} is better',
                      style: const TextStyle(fontSize: 14, color: EngineeringStyle.textSecondary),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => showRunEngineeringRoundDialog(context, campaign),
                child: const Text('Suggest next round →'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  'Best variant',
                  best?.sequence == campaign.wildtypeSequence ? 'Wildtype' : (best == null ? '—' : _bestLabel(best)),
                  best?.fitness != null ? '${best!.fitness} ${campaign.measurementUnit}' : null,
                  EngineeringStyle.success,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard(
                  'Over wildtype',
                  overWildtype == null ? '—' : overWildtype.toStringAsFixed(2),
                  campaign.wildtypeFitness == null ? null : 'baseline ${campaign.wildtypeFitness}',
                  EngineeringStyle.success,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _statCard('Rounds completed', '${campaign.rounds.length}', null, null)),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard('Variants measured', '${campaign.measurements.length}', null, null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: EngineeringStyle.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Best measured value, round by round',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: series.length > 1
                      ? LineChart(
                          LineChartData(
                            lineBarsData: [
                              LineChartBarData(
                                spots: [for (final (round, value) in series) FlSpot(round.toDouble(), value)],
                                color: EngineeringStyle.accent,
                              ),
                            ],
                          ),
                        )
                      : const Center(
                          child: Text(
                            'Will chart here once a few rounds are measured.',
                            style: TextStyle(color: EngineeringStyle.textMuted, fontSize: 13),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildRecentRounds(context),
        ],
      ),
    );
  }

  String _bestLabel(MeasuredVariant variant) =>
      variant.substitutions.isEmpty ? 'Wildtype' : variant.substitutions.map((s) => s.toString()).join(' + ');

  Widget _statCard(String label, String value, String? subtitle, Color? valueColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EngineeringStyle.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: EngineeringStyle.textMuted)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: valueColor)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: EngineeringStyle.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentRounds(BuildContext context) {
    final rounds = campaign.rounds.reversed.take(3).toList();
    return Container(
      decoration: EngineeringStyle.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent rounds', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                TextButton(onPressed: onOpenHistory, child: const Text('View all →')),
              ],
            ),
          ),
          if (rounds.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text('No rounds run yet.', style: TextStyle(color: EngineeringStyle.textMuted, fontSize: 13)),
            ),
          for (final round in rounds)
            InkWell(
              onTap: () => onOpenRound(campaign.rounds.indexOf(round)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: EngineeringStyle.dividerLight))),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text('Round ${round.sentConfig.iteration}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Text(
                        '${round.result.suggestions.length} suggested',
                        style: const TextStyle(fontSize: 13, color: EngineeringStyle.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/style/engineering_style.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_candidates_grid_view.dart';
import 'package:flutter/material.dart';

/// Every variant suggested so far, across all rounds, filterable by measurement status.
class EngineeringHistoryView extends StatefulWidget {
  final EngineeringCampaign campaign;

  const EngineeringHistoryView({required this.campaign, super.key});

  @override
  State<EngineeringHistoryView> createState() => _EngineeringHistoryViewState();
}

class _EngineeringHistoryViewState extends State<EngineeringHistoryView> {
  EngineeringMeasuredFilter _filter = EngineeringMeasuredFilter.all;

  int _countExpressed() => widget.campaign.measurements.values.where((v) => !v.didNotExpress).length;

  int _countDidNotExpress() => widget.campaign.measurements.values.where((v) => v.didNotExpress).length;

  @override
  Widget build(BuildContext context) {
    final campaign = widget.campaign;
    if (campaign.rounds.isEmpty) {
      return const Center(child: Text('No rounds run yet.', style: TextStyle(color: EngineeringStyle.textMuted)));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('All rounds', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Every variant suggested so far, across all rounds',
            style: TextStyle(fontSize: 13, color: EngineeringStyle.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _filterChip('All', EngineeringMeasuredFilter.all, campaign.measurements.length),
              const SizedBox(width: 8),
              _filterChip('Measured', EngineeringMeasuredFilter.measured, _countExpressed()),
              const SizedBox(width: 8),
              _filterChip('Did not express', EngineeringMeasuredFilter.didNotExpress, _countDidNotExpress()),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: EngineeringCandidatesGridView(
              campaign: campaign,
              displayedRound: null,
              filter: _filter,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, EngineeringMeasuredFilter filter, int count) {
    final selected = _filter == filter;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      selectedColor: EngineeringStyle.accent,
      labelStyle: TextStyle(color: selected ? Colors.white : EngineeringStyle.textPrimary, fontWeight: FontWeight.w600),
      backgroundColor: EngineeringStyle.surface,
      side: const BorderSide(color: EngineeringStyle.border),
      onSelected: (_) => setState(() => _filter = filter),
    );
  }
}

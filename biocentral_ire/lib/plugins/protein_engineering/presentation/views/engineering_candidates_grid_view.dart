import 'package:biocentral/plugins/protein_engineering/bloc/engineering_hub_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/util/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pluto_grid/pluto_grid.dart';

/// When [displayedRound] is null, shows every round combined with a round column.
class EngineeringCandidatesGridView extends StatefulWidget {
  final EngineeringCampaign campaign;
  final EngineeringRound? displayedRound;

  const EngineeringCandidatesGridView({
    required this.campaign,
    required this.displayedRound,
    super.key,
  });

  @override
  State<EngineeringCandidatesGridView> createState() => _EngineeringCandidatesGridViewState();
}

class _EngineeringCandidatesGridViewState extends State<EngineeringCandidatesGridView> {
  final List<PlutoColumn> _columns = <PlutoColumn>[
    PlutoColumn(title: 'Rank', field: 'ranking', readOnly: true, type: PlutoColumnType.text()),
    PlutoColumn(title: 'Variant', field: 'variant', readOnly: true, type: PlutoColumnType.text()),
    PlutoColumn(title: 'Predicted value', field: 'prediction', readOnly: true, type: PlutoColumnType.text()),
    PlutoColumn(
        title: 'Uncertainty',
        field: 'uncertainty',
        readOnly: true,
        type: PlutoColumnType.number(format: '#,###.############')),
    PlutoColumn(
        title: 'Pick score',
        field: 'score',
        readOnly: true,
        type: PlutoColumnType.number(format: '#,###.############')),
    PlutoColumn(title: 'Measured', field: 'measured', readOnly: true, type: PlutoColumnType.text()),
  ];

  bool get _showAllRounds => widget.displayedRound == null;

  String _label(String parentSequence, String entityId) {
    try {
      return formatSubstitutions(parseMutationDescriptor(entityId));
    } on UnresolvableVariantException {
      return '$entityId (not resolvable yet)';
    }
  }

  String? _measuredValue(String parentSequence, String entityId) {
    try {
      final sequence = applySubstitutions(parentSequence, parseMutationDescriptor(entityId));
      final variant = sequence != null ? widget.campaign.measurements[sequence] : null;
      if (variant == null) {
        return null;
      }
      return variant.didNotExpress ? 'did not express' : variant.fitness.toString();
    } on UnresolvableVariantException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EngineeringHubBloc, EngineeringHubState>(
      buildWhen: (previous, current) => previous.selectedCampaign != current.selectedCampaign,
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PlutoGrid(
            key: UniqueKey(),
            mode: PlutoGridMode.selectWithOneTap,
            columns: _showAllRounds ? [_roundColumn(), ..._columns] : _columns,
            rows: _showAllRounds ? _buildAllRows() : _buildRows(widget.displayedRound!),
          ),
        );
      },
    );
  }

  PlutoColumn _roundColumn() {
    return PlutoColumn(title: 'Round', field: 'round', readOnly: true, type: PlutoColumnType.number());
  }

  List<PlutoRow> _buildRows(EngineeringRound round) {
    final suggestionSet = round.result.suggestions.toSet();
    final suggestions = round.result.results.where((r) => suggestionSet.contains(r.entityId)).toList();
    var index = 0;
    return suggestions.map((result) {
      return PlutoRow(cells: {
        'ranking': PlutoCell(value: ++index),
        'variant': PlutoCell(value: _label(round.parentSequence, result.entityId)),
        'prediction': PlutoCell(value: result.prediction),
        'uncertainty': PlutoCell(value: result.uncertainty.toStringAsFixed(Constants.maxDoublePrecision)),
        'score': PlutoCell(value: result.score.toStringAsFixed(Constants.maxDoublePrecision)),
        'measured': PlutoCell(value: _measuredValue(round.parentSequence, result.entityId) ?? ''),
      });
    }).toList();
  }

  List<PlutoRow> _buildAllRows() {
    final rows = <PlutoRow>[];
    var index = 0;
    for (final round in widget.campaign.rounds) {
      final suggestionSet = round.result.suggestions.toSet();
      final suggestions = round.result.results.where((r) => suggestionSet.contains(r.entityId)).toList();
      for (final result in suggestions) {
        rows.add(PlutoRow(cells: {
          'round': PlutoCell(value: round.sentConfig.iteration),
          'ranking': PlutoCell(value: ++index),
          'variant': PlutoCell(value: _label(round.parentSequence, result.entityId)),
          'prediction': PlutoCell(value: result.prediction),
          'uncertainty': PlutoCell(value: result.uncertainty.toStringAsFixed(Constants.maxDoublePrecision)),
          'score': PlutoCell(value: result.score.toStringAsFixed(Constants.maxDoublePrecision)),
          'measured': PlutoCell(value: _measuredValue(round.parentSequence, result.entityId) ?? ''),
        }));
      }
    }
    return rows;
  }
}

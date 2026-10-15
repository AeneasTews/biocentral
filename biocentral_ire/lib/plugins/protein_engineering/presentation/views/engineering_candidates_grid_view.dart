import 'package:biocentral/plugins/protein_engineering/bloc/engineering_hub_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/domain/structure_sequence.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/style/engineering_style.dart';
import 'package:biocentral/sdk/util/constants.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pluto_grid/pluto_grid.dart';

/// Which rows [EngineeringCandidatesGridView] shows, by measurement status.
enum EngineeringMeasuredFilter { all, measured, didNotExpress }

/// An unmeasured candidate's value, entered via a dialog but not yet submitted.
class PendingMeasurement {
  final MeasuredVariant base;
  double? value;
  bool didNotExpress;

  PendingMeasurement({required this.base, this.value, this.didNotExpress = false});

  String get displayLabel => didNotExpress ? 'Did not express' : (value?.toString() ?? '');
}

/// Shows one round's candidates, or every round combined with a round column when
/// [displayedRound] is null. A row is selected via [onCandidateSelected]; an unmeasured
/// row opens a dialog to fill in [pending] via [onStartEditing].
class EngineeringCandidatesGridView extends StatefulWidget {
  final EngineeringCampaign campaign;
  final EngineeringRound? displayedRound;
  final String? selectedSequence;
  final EngineeringMeasuredFilter filter;
  final Map<String, PendingMeasurement> pending;
  final Set<String> lockedSequences;
  final int editVersion;
  final ValueChanged<StructureCandidate?>? onCandidateSelected;
  final ValueChanged<MeasuredVariant>? onStartEditing;
  final ValueChanged<PendingMeasurement>? onEditPending;
  final ValueChanged<String>? onCancelEditing;

  const EngineeringCandidatesGridView({
    required this.campaign,
    required this.displayedRound,
    this.selectedSequence,
    this.filter = EngineeringMeasuredFilter.all,
    this.pending = const {},
    this.lockedSequences = const {},
    this.editVersion = 0,
    this.onCandidateSelected,
    this.onStartEditing,
    this.onEditPending,
    this.onCancelEditing,
    super.key,
  });

  @override
  State<EngineeringCandidatesGridView> createState() => _EngineeringCandidatesGridViewState();
}

class _EngineeringCandidatesGridViewState extends State<EngineeringCandidatesGridView> {
  List<PlutoColumn> _columns() {
    return [
      if (_showAllRounds)
        PlutoColumn(title: 'Round', field: 'round', readOnly: true, type: PlutoColumnType.number(), width: 64),
      PlutoColumn(title: 'Rank', field: 'ranking', readOnly: true, type: PlutoColumnType.text(), width: 50),
      PlutoColumn(title: 'Variant', field: 'variant', readOnly: true, type: PlutoColumnType.text(), width: 140),
      PlutoColumn(title: 'Predicted', field: 'prediction', readOnly: true, type: PlutoColumnType.text(), width: 85),
      PlutoColumn(
        title: 'Uncertainty',
        field: 'uncertainty',
        readOnly: true,
        type: PlutoColumnType.number(format: '#,###.############'),
        width: 95,
      ),
      PlutoColumn(
        title: 'Score',
        field: 'score',
        readOnly: true,
        type: PlutoColumnType.number(format: '#,###.############'),
        width: 85,
      ),
      PlutoColumn(
        title: 'Measured',
        field: 'measured',
        readOnly: true,
        type: PlutoColumnType.text(),
        width: 150,
        renderer: _measuredCellRenderer,
      ),
    ];
  }

  bool get _showAllRounds => widget.displayedRound == null;

  String _label(String entityId, List<Substitution> substitutions) {
    if (substitutions.isEmpty) {
      return '$entityId (not resolvable yet)';
    }
    return formatSubstitutions(substitutions);
  }

  Widget _measuredCellRenderer(PlutoColumnRendererContext context) {
    final sequence = context.row.cells['sequence']?.value as String?;
    final pendingVariant = context.row.cells['pendingVariant']?.value as MeasuredVariant?;
    if (sequence == null) {
      return const SizedBox.shrink();
    }

    final existing = widget.campaign.measurements[sequence];
    if (existing != null) {
      final label = existing.didNotExpress ? 'Did not express' : existing.fitness.toString();
      return EngineeringStyle.chip(label, existing.didNotExpress ? EngineeringStyle.danger : EngineeringStyle.success);
    }

    if (widget.lockedSequences.contains(sequence)) {
      final entry = widget.pending[sequence];
      return EngineeringStyle.chip('${entry?.displayLabel ?? ''} (pending)', EngineeringStyle.warning);
    }

    final entry = widget.pending[sequence];
    if (entry != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onEditPending?.call(entry),
              child: Text(
                entry.displayLabel.isEmpty ? 'tap to edit' : entry.displayLabel,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: EngineeringStyle.accent),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            onPressed: () => widget.onCancelEditing?.call(sequence),
          ),
        ],
      );
    }

    if (pendingVariant == null || widget.onStartEditing == null) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: () => widget.onStartEditing!(pendingVariant),
      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
      child: const Text('+ Enter value', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EngineeringHubBloc, EngineeringHubState>(
      buildWhen: (previous, current) => previous.selectedCampaign != current.selectedCampaign,
      builder: (context, state) {
        return PlutoGrid(
          // Stable unless the underlying data, or an edit/lock/selection action, changes.
          key: ValueKey(
            '${widget.campaign.internalName()}-${widget.displayedRound?.sentConfig.iteration}-'
            '${widget.filter.name}-${widget.campaign.measurements.length}-${widget.editVersion}',
          ),
          mode: PlutoGridMode.selectWithOneTap,
          columns: _columns(),
          rows: _showAllRounds ? _buildAllRows() : _buildRows(widget.displayedRound!),
          configuration: const PlutoGridConfiguration(
            columnSize: PlutoGridColumnSizeConfig(autoSizeMode: PlutoAutoSizeMode.scale),
          ),
          rowColorCallback: (rowColorContext) {
            final sequence = rowColorContext.row.cells['sequence']?.value as String?;
            return sequence != null && sequence == widget.selectedSequence ? EngineeringStyle.accentSoft : Colors.white;
          },
          onSelected: (event) {
            final sequence = event.row?.cells['sequence']?.value as String?;
            final label = event.row?.cells['variant']?.value as String?;
            if (widget.onCandidateSelected == null) {
              return;
            }
            widget.onCandidateSelected!(
              sequence != null && label != null ? StructureCandidate(label: label, sequence: sequence) : null,
            );
          },
        );
      },
    );
  }

  PlutoRow _rowFor(EngineeringRound round, ActiveLearningResult result, int rank, {int? roundNumber}) {
    List<Substitution> substitutions = const [];
    String? sequence;
    try {
      substitutions = parseMutationDescriptor(result.entityId);
      sequence = applySubstitutions(round.parentSequence, substitutions);
    } on UnresolvableVariantException {
      // entity_id isn't a descriptor yet; leave substitutions empty and sequence null.
    }
    final pending = sequence != null && widget.campaign.measurements[sequence] == null
        ? MeasuredVariant(
            seqId: result.entityId,
            sequence: sequence,
            parentSequence: round.parentSequence,
            substitutions: substitutions,
            roundFound: round.sentConfig.iteration,
          )
        : null;
    return PlutoRow(cells: {
      if (roundNumber != null) 'round': PlutoCell(value: roundNumber),
      'ranking': PlutoCell(value: rank),
      'variant': PlutoCell(value: _label(result.entityId, substitutions)),
      'prediction': PlutoCell(value: _formatted(result.prediction)),
      'uncertainty': PlutoCell(value: result.uncertainty.toStringAsFixed(Constants.maxDoublePrecision)),
      'score': PlutoCell(value: result.score.toStringAsFixed(Constants.maxDoublePrecision)),
      'measured': PlutoCell(value: ''),
      'sequence': PlutoCell(value: sequence),
      'pendingVariant': PlutoCell(value: pending),
    });
  }

  String _formatted(String rawNumber) {
    final value = double.tryParse(rawNumber);
    return value == null ? rawNumber : value.toStringAsFixed(Constants.maxDoublePrecision);
  }

  List<ActiveLearningResult> _suggestions(EngineeringRound round) {
    final suggestionSet = round.result.suggestions.toSet();
    return round.result.results.where((r) => suggestionSet.contains(r.entityId)).where(_matchesFilter(round)).toList();
  }

  bool Function(ActiveLearningResult) _matchesFilter(EngineeringRound round) {
    if (widget.filter == EngineeringMeasuredFilter.all) {
      return (_) => true;
    }
    return (result) {
      String? sequence;
      try {
        sequence = applySubstitutions(round.parentSequence, parseMutationDescriptor(result.entityId));
      } on UnresolvableVariantException {
        return false;
      }
      final measured = sequence == null ? null : widget.campaign.measurements[sequence];
      return switch (widget.filter) {
        EngineeringMeasuredFilter.measured => measured != null && !measured.didNotExpress,
        EngineeringMeasuredFilter.didNotExpress => measured != null && measured.didNotExpress,
        EngineeringMeasuredFilter.all => true,
      };
    };
  }

  List<PlutoRow> _buildRows(EngineeringRound round) {
    var rank = 0;
    return _suggestions(round).map((result) => _rowFor(round, result, ++rank)).toList();
  }

  List<PlutoRow> _buildAllRows() {
    final rows = <PlutoRow>[];
    var rank = 0;
    for (final round in widget.campaign.rounds) {
      for (final result in _suggestions(round)) {
        rows.add(_rowFor(round, result, ++rank, roundNumber: round.sentConfig.iteration));
      }
    }
    return rows;
  }
}

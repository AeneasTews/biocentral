import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_hub_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/bloc/biocentral_command_availability.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_command_widget.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_status_indicator.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class _CandidateRow {
  final String entityId;
  final String? sequence; // null if entityId could not be resolved to a substitution
  final List<Substitution> substitutions;
  final ActiveLearningResult? result;
  final TextEditingController valueController = TextEditingController();
  bool didNotExpress = false;

  _CandidateRow({required this.entityId, required this.sequence, required this.substitutions, required this.result});
}

class EnterMeasurementsCommandDisplay extends StatefulWidget {
  const EnterMeasurementsCommandDisplay({super.key});

  @override
  State<EnterMeasurementsCommandDisplay> createState() => _EnterMeasurementsCommandDisplayState();
}

class _EnterMeasurementsCommandDisplayState extends State<EnterMeasurementsCommandDisplay> {
  EngineeringRound? _loadedRound;
  List<_CandidateRow> _rows = [];

  void _loadRound(EngineeringCampaign? campaign) {
    final round = campaign?.rounds.isNotEmpty == true ? campaign!.rounds.last : null;
    if (identical(round, _loadedRound)) {
      return;
    }
    _loadedRound = round;
    if (round == null) {
      _rows = [];
      return;
    }
    final resultsById = {for (final result in round.result.results) result.entityId: result};
    _rows = round.result.suggestions
        .where((entityId) => !campaign!.measurements.values.any((v) => v.seqId == entityId))
        .map((entityId) {
      String? sequence;
      List<Substitution> substitutions = const [];
      try {
        substitutions = parseMutationDescriptor(entityId);
        sequence = applySubstitutions(round.parentSequence, substitutions);
      } on UnresolvableVariantException {
        sequence = null;
      }
      return _CandidateRow(
          entityId: entityId, sequence: sequence, substitutions: substitutions, result: resultsById[entityId]);
    }).toList();
  }

  AddEngineeringMeasurementsCommand? collectCommand(EngineeringCampaign? campaign) {
    if (campaign == null) {
      return null;
    }
    final round = _loadedRound;
    if (round == null) {
      return null;
    }

    final newMeasurements = <MeasuredVariant>[];
    for (final row in _rows) {
      final sequence = row.sequence;
      if (sequence == null) {
        continue;
      }
      final value = double.tryParse(row.valueController.text);
      if (!row.didNotExpress && value == null) {
        continue;
      }
      newMeasurements.add(MeasuredVariant(
        seqId: row.entityId,
        sequence: sequence,
        parentSequence: round.parentSequence,
        substitutions: row.substitutions,
        roundFound: round.sentConfig.iteration,
        fitness: row.didNotExpress ? null : value,
      ));
    }
    if (newMeasurements.isEmpty) {
      return null;
    }

    return AddEngineeringMeasurementsCommand(
      engineeringRepository: context.read<EngineeringRepository>(),
      campaign: campaign,
      newMeasurements: newMeasurements,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EngineeringHubBloc, EngineeringHubState>(
      builder: (context, hubState) {
        _loadRound(hubState.selectedCampaign);
        return BiocentralCommandWidget(
          icon: const Icon(Icons.checklist_outlined),
          name: 'Enter what you measured',
          description: 'Feed this round\'s bench results back into the campaign',
          executeButtonLabel: 'Save measurements',
          parameterSelection: buildParameterSelection,
          collectCommand: () => collectCommand(hubState.selectedCampaign),
          visualizeResult: (log) => BiocentralStatusIndicator(metaData: log.metaData),
          commandAvailability: BiocentralCommandAvailability(
            available: _loadedRound != null,
            unavailableMessage: 'Run a round for a campaign first',
          ),
        );
      },
    );
  }

  Widget buildParameterSelection() {
    if (_rows.isEmpty) {
      return const Text('Nothing to enter -- every suggested variant from the latest round is already measured.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _rows.map(buildRow).toList(),
    );
  }

  Widget buildRow(_CandidateRow row) {
    final label = row.substitutions.isNotEmpty ? formatSubstitutions(row.substitutions) : row.entityId;
    final predicted = row.result?.prediction;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(row.sequence == null ? '$label (unresolvable)' : label)),
          if (predicted != null) SizedBox(width: 100, child: Text('predicted: $predicted')),
          Expanded(
            child: row.didNotExpress
                ? const Text('Did not express')
                : TextField(
                    controller: row.valueController,
                    keyboardType: TextInputType.number,
                    enabled: row.sequence != null,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Measured value'),
                    onChanged: (_) => setState(() {}),
                  ),
          ),
          Checkbox(
            value: row.didNotExpress,
            onChanged: row.sequence == null ? null : (value) => setState(() => row.didNotExpress = value ?? false),
          ),
          const Text('did not express'),
        ],
      ),
    );
  }
}

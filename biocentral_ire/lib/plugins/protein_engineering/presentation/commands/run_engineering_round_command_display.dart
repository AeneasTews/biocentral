import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_hub_bloc.dart';
import 'package:biocentral/sdk/bloc/biocentral_command.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/bloc/biocentral_command_availability.dart';
import 'package:biocentral/sdk/domain/biocentral_api_repository.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_command_widget.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_discrete_selection.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_status_indicator.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum _StartingPoint { wildtype, bestSoFar }

class RunEngineeringRoundCommandDisplay extends StatefulWidget {
  const RunEngineeringRoundCommandDisplay({super.key});

  @override
  State<RunEngineeringRoundCommandDisplay> createState() => _RunEngineeringRoundCommandDisplayState();

  static Widget visualizeIterationResult(BiocentralCommandLog result) {
    final commandResult = result.result?.result;
    if (commandResult == null || commandResult is! ActiveLearningIterationResult) {
      return BiocentralStatusIndicator(metaData: result.metaData);
    }
    final iterationResult = commandResult;
    return Column(
      children: [
        BiocentralStatusIndicator(metaData: result.metaData),
        const Text('Suggestions:'),
        ...iterationResult.suggestions.map((entityId) => Text(_displayLabel(entityId))),
      ],
    );
  }

  static String _displayLabel(String entityId) {
    try {
      return formatSubstitutions(parseMutationDescriptor(entityId));
    } on UnresolvableVariantException {
      return '$entityId (not resolvable yet)';
    }
  }
}

class _RunEngineeringRoundCommandDisplayState extends State<RunEngineeringRoundCommandDisplay> {
  int _nSuggestions = 8;
  double _coefficient = 0.5;
  _StartingPoint _startingPoint = _StartingPoint.wildtype;

  MeasuredVariant? _bestMeasuredVariant(EngineeringCampaign campaign) {
    final measured = campaign.measurements.values.where((variant) => variant.fitness != null).toList();
    if (measured.isEmpty) {
      return null;
    }
    final maximize = campaign.config.optimizationMode == ActiveLearningOptimizationMode.MAXIMIZE;
    measured.sort((a, b) => maximize ? b.fitness!.compareTo(a.fitness!) : a.fitness!.compareTo(b.fitness!));
    return measured.first;
  }

  String _parentSequence(EngineeringCampaign campaign) {
    if (_startingPoint == _StartingPoint.bestSoFar) {
      return _bestMeasuredVariant(campaign)?.sequence ?? campaign.wildtypeSequence;
    }
    return campaign.wildtypeSequence;
  }

  RunEngineeringRoundCommand? collectCommand(EngineeringCampaign? campaign) {
    if (campaign == null || _nSuggestions < 1) {
      return null;
    }

    final measuredTrainingData = campaign.measurements.values.where((variant) => variant.fitness != null);
    if (measuredTrainingData.isEmpty) {
      return null;
    }

    final trainingData = measuredTrainingData
        .map((variant) => SequenceData((b) => b
          ..seqId = variant.seqId
          ..seq = variant.sequence
          ..set_ = 'train'
          ..label = variant.fitness.toString()))
        .toList();

    final parentSequence = _parentSequence(campaign);

    final iterationConfig = ActiveLearningEngineeringIterationConfig((b) => b
      ..iteration = campaign.rounds.length + 1
      ..baseSequences = ListBuilder<String>([parentSequence])
      ..trainingData = ListBuilder<SequenceData>(trainingData)
      ..coefficient = _coefficient
      ..nSuggestions = _nSuggestions);

    return RunEngineeringRoundCommand(
      apiRepository: context.read<BiocentralAPIRepository>(),
      engineeringRepository: context.read<EngineeringRepository>(),
      campaign: campaign,
      iterationConfig: iterationConfig,
      parentSequence: parentSequence,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EngineeringHubBloc, EngineeringHubState>(
      builder: (context, hubState) {
        final campaign = hubState.selectedCampaign;
        return BiocentralCommandWidget(
          icon: const Icon(Icons.auto_awesome_outlined),
          name: 'Suggest next variants',
          description: 'Generate and score mutants of the wildtype, and suggest the next batch to test',
          executeButtonLabel: 'Suggest variants',
          parameterSelection: () => buildParameterSelection(campaign),
          collectCommand: () => collectCommand(campaign),
          visualizeResult: RunEngineeringRoundCommandDisplay.visualizeIterationResult,
          commandAvailability: campaign == null
              ? BiocentralCommandAvailability(available: false, unavailableMessage: 'Select a campaign first')
              : BiocentralCommandAvailability.always(),
        );
      },
    );
  }

  Widget buildParameterSelection(EngineeringCampaign? campaign) {
    if (campaign == null) {
      return const Text('Select a campaign first.');
    }
    final measuredCount = campaign.measurements.values.where((variant) => variant.fitness != null).length;
    final best = _bestMeasuredVariant(campaign);

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Using $measuredCount measurement(s) entered so far.'),
          const SizedBox(height: 12),
          const Text('How many variants can you test this round?'),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _nSuggestions > 1 ? () => setState(() => _nSuggestions--) : null,
              ),
              Text('$_nSuggestions', style: const TextStyle(fontSize: 18)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _nSuggestions++),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('How adventurous should the picks be?'),
          Row(
            children: [
              const Text('Stick to the best'),
              Expanded(
                child: Slider(
                  value: _coefficient,
                  divisions: 10,
                  label: _coefficient.toStringAsFixed(1),
                  onChanged: (value) => setState(() => _coefficient = value),
                ),
              ),
              const Text('Search widely'),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Build variants from'),
          BiocentralDiscreteSelection<_StartingPoint>(
            title: 'Starting point',
            initialValue: _startingPoint,
            selectableValues: best == null ? const [_StartingPoint.wildtype] : _StartingPoint.values,
            displayConversion: (point) => switch (point) {
              _StartingPoint.wildtype => 'Wildtype',
              _StartingPoint.bestSoFar => 'Best so far${best != null ? ' (${best.fitness})' : ''}',
            },
            onChangedCallback: (point) => setState(() => _startingPoint = point ?? _StartingPoint.wildtype),
          ),
          if (measuredCount == 0)
            const Padding(
              padding: EdgeInsets.only(top: 12.0),
              child: Text(
                'No measurements entered yet -- enter at least the wildtype value before running a round.',
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

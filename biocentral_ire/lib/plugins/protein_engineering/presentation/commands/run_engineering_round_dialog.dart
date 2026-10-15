import 'package:biocentral/biocentral/bloc/biocentral_sidebar_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/style/engineering_style.dart';
import 'package:biocentral/sdk/biocentral_sdk.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum _StartingPoint { wildtype, bestSoFar }

/// Opens a compact dialog for configuring and submitting the next round.
Future<void> showRunEngineeringRoundDialog(BuildContext context, EngineeringCampaign campaign) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _RunEngineeringRoundDialogContent(campaign: campaign),
      ),
    ),
  );
}

class _RunEngineeringRoundDialogContent extends StatefulWidget {
  final EngineeringCampaign campaign;

  const _RunEngineeringRoundDialogContent({required this.campaign});

  @override
  State<_RunEngineeringRoundDialogContent> createState() => _RunEngineeringRoundDialogContentState();
}

class _RunEngineeringRoundDialogContentState extends State<_RunEngineeringRoundDialogContent> {
  int _nSuggestions = 8;
  double _coefficient = 0.5;
  _StartingPoint _startingPoint = _StartingPoint.wildtype;

  MeasuredVariant? _bestMeasuredVariant() {
    final measured = widget.campaign.measurements.values.where((variant) => variant.fitness != null).toList();
    if (measured.isEmpty) {
      return null;
    }
    final maximize = widget.campaign.config.optimizationMode == ActiveLearningOptimizationMode.MAXIMIZE;
    measured.sort((a, b) => maximize ? b.fitness!.compareTo(a.fitness!) : a.fitness!.compareTo(b.fitness!));
    return measured.first;
  }

  String _parentSequence(MeasuredVariant? best) {
    if (_startingPoint == _StartingPoint.bestSoFar) {
      return best?.sequence ?? widget.campaign.wildtypeSequence;
    }
    return widget.campaign.wildtypeSequence;
  }

  void _submit() {
    final campaign = widget.campaign;
    final measuredTrainingData = campaign.measurements.values.where((variant) => variant.fitness != null);
    if (measuredTrainingData.isEmpty) {
      return;
    }

    final trainingData = measuredTrainingData
        .map((variant) => SequenceData((b) => b
          ..seqId = variant.seqId
          ..seq = variant.sequence
          ..set_ = 'train'
          ..label = variant.fitness.toString()))
        .toList();

    final parentSequence = _parentSequence(_bestMeasuredVariant());
    final iterationConfig = ActiveLearningEngineeringIterationConfig((b) => b
      ..iteration = campaign.rounds.length + 1
      ..baseSequences = ListBuilder<String>([parentSequence])
      ..trainingData = ListBuilder<SequenceData>(trainingData)
      ..coefficient = _coefficient
      ..nSuggestions = _nSuggestions);

    final command = RunEngineeringRoundCommand(
      apiRepository: context.read<BiocentralAPIRepository>(),
      engineeringRepository: context.read<EngineeringRepository>(),
      campaign: campaign,
      iterationConfig: iterationConfig,
      parentSequence: parentSequence,
    );

    context
        .read<BiocentralSideBarBloc>()
        .add(BiocentralSideBarChangeVisibilityEvent(displayMode: BiocentralSideBarDisplayMode.commandLog, force: true));
    context.read<BiocentralCommandBloc>().add(
          BiocentralCommandExecuteEvent(
            command: command,
            visualizeResult: (log) => BiocentralStatusIndicator(metaData: log.metaData),
            autoAccept: false,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final campaign = widget.campaign;
    final measuredCount = campaign.measurements.values.where((variant) => variant.fitness != null).length;
    final best = _bestMeasuredVariant();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Suggest next round', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Using $measuredCount measurement(s) entered so far.',
              style: const TextStyle(fontSize: 13, color: EngineeringStyle.textSecondary)),
          const SizedBox(height: 18),
          const Text('How many variants can you test this round?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _nSuggestions > 1 ? () => setState(() => _nSuggestions--) : null,
              ),
              Text('$_nSuggestions', style: const TextStyle(fontSize: 18)),
              IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _nSuggestions++)),
            ],
          ),
          const SizedBox(height: 10),
          const Text('How adventurous should the picks be?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Row(
            children: [
              const Text('Stick to the best', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _coefficient,
                  divisions: 10,
                  activeColor: EngineeringStyle.accent,
                  label: _coefficient.toStringAsFixed(1),
                  onChanged: (value) => setState(() => _coefficient = value),
                ),
              ),
              const Text('Search widely', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Build variants from', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
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
                'No measurements entered yet — enter at least the wildtype value before running a round.',
                style: TextStyle(color: EngineeringStyle.danger, fontSize: 12),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: measuredCount == 0 ? null : _submit, child: const Text('Suggest variants')),
            ],
          ),
        ],
      ),
    );
  }
}

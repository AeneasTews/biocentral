import 'package:bio_flutter/bio_flutter.dart' show Protein;
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/domain/fasta_utils.dart';
import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/domain/sequence_validation.dart';
import 'package:biocentral/plugins/proteins/domain/protein_repository.dart';
import 'package:biocentral/sdk/bloc/biocentral_command_availability.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_command_widget.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_discrete_selection.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_file_path_selection.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_status_indicator.dart';
import 'package:biocentral/sdk/util/widget_util.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum _WildtypeSource { fromProject, fasta, paste }

class _SeedRow {
  final TextEditingController substitutionController = TextEditingController();
  final TextEditingController valueController = TextEditingController();
}

class NewEngineeringCampaignCommandDisplay extends StatefulWidget {
  const NewEngineeringCampaignCommandDisplay({super.key});

  @override
  State<NewEngineeringCampaignCommandDisplay> createState() => _NewEngineeringCampaignCommandDisplayState();
}

class _NewEngineeringCampaignCommandDisplayState extends State<NewEngineeringCampaignCommandDisplay> {
  static const String _defaultEmbedderWireName = 'facebook/esm2_t33_650M_UR50D';
  static const ActiveLearningModelType _defaultModelType = ActiveLearningModelType.GAUSSIAN_PROCESS;
  static const int _defaultSeed = 42;

  _WildtypeSource _wildtypeSource = _WildtypeSource.fromProject;
  Protein? _selectedProjectProtein;
  String? _wildtypeId;
  String? _wildtypeSequence;
  String? _wildtypeError;

  String _campaignName = 'Engineering-Campaign';
  String _measurementName = '';
  String _measurementUnit = '';
  ActiveLearningOptimizationMode _direction = ActiveLearningOptimizationMode.MAXIMIZE;

  final TextEditingController _wildtypeFitnessController = TextEditingController();
  final List<_SeedRow> _seedRows = [];

  void _setWildtype(String? id, String? sequence) {
    setState(() {
      _wildtypeId = id;
      _wildtypeSequence = sequence;
      _wildtypeError = null;
      if (sequence != null) {
        final invalidIndex = findInvalidResidueIndex(sequence);
        if (invalidIndex != null) {
          _wildtypeError = 'Position ${invalidIndex + 1} ("${sequence[invalidIndex]}") is not one of the '
              '20 standard amino acids.';
        }
      }
    });
  }

  Future<void> _loadFastaFile(XFile xFile) async {
    try {
      final content = await xFile.readAsString();
      final entry = parseFirstFastaEntry(content);
      if (entry == null) {
        setState(() => _wildtypeError = 'No sequence found in file.');
        return;
      }
      _setWildtype(entry.id, entry.sequence);
    } catch (e) {
      setState(() => _wildtypeError = 'Could not read FASTA file: $e');
    }
  }

  NewEngineeringCampaignCommand? collectCommand() {
    final wildtypeSequence = _wildtypeSequence;
    final wildtypeId = _wildtypeId;
    if (wildtypeSequence == null || wildtypeId == null || _wildtypeError != null) {
      return null;
    }
    if (_measurementName.trim().isEmpty) {
      return null;
    }

    final campaignConfig = ActiveLearningEngineeringCampaignConfig((b) => b
      ..name = _campaignName
      ..embedderName = _defaultEmbedderWireName
      ..modelType = _defaultModelType
      ..optimizationMode = _direction
      ..seed = _defaultSeed
      ..wildtypeSequence = wildtypeSequence);

    final wildtypeFitness = double.tryParse(_wildtypeFitnessController.text);

    final seedMeasurements = <SeedMeasurement>[];
    for (final row in _seedRows) {
      final substitutionText = row.substitutionController.text.trim();
      final value = double.tryParse(row.valueController.text);
      if (substitutionText.isEmpty || value == null) {
        continue;
      }
      try {
        final substitutions = parseMutationDescriptor(substitutionText);
        seedMeasurements.add(SeedMeasurement(substitutions: substitutions, fitness: value));
      } on UnresolvableVariantException {
        // Ignore invalid seed measurements without rejecting the campaign.
      }
    }

    return NewEngineeringCampaignCommand(
      engineeringRepository: context.read<EngineeringRepository>(),
      campaignConfig: campaignConfig,
      wildtypeId: wildtypeId,
      wildtypeSequence: wildtypeSequence,
      measurementName: _measurementName.trim(),
      measurementUnit: _measurementUnit.trim(),
      wildtypeFitness: wildtypeFitness,
      seedMeasurements: seedMeasurements,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BiocentralCommandWidget(
      icon: const Icon(Icons.science_outlined),
      name: 'Start a new protein engineering campaign',
      description: 'Suggest mutations of a wildtype protein, measure them, and feed the results back',
      executeButtonLabel: 'Create campaign',
      parameterSelection: buildParameterSelection,
      collectCommand: collectCommand,
      visualizeResult: (log) => BiocentralStatusIndicator(metaData: log.metaData),
      commandAvailability: BiocentralCommandAvailability.always(),
    );
  }

  Widget buildParameterSelection() {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        children: [
          buildCampaignNameInput(),
          buildWildtypeSourceSelection(),
          buildWildtypeSourceInput(),
          buildWildtypeSummary(),
          withCondition(condition: _wildtypeSequence != null && _wildtypeError == null, childFunction: buildGoal),
          withCondition(
            condition: _measurementName.trim().isNotEmpty,
            childFunction: buildSeedMeasurements,
          ),
        ].withPadding(const Padding(padding: EdgeInsetsGeometry.all(8.0))),
      ),
    );
  }

  Widget buildCampaignNameInput() {
    return TextFormField(
      initialValue: _campaignName,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Campaign name',
      ),
      onChanged: (value) {
        setState(() {
          _campaignName = value.trim().isEmpty ? 'Engineering-Campaign' : value.trim();
        });
      },
    );
  }

  Widget buildWildtypeSourceSelection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Which protein are you engineering?'),
        BiocentralDiscreteSelection<_WildtypeSource>(
          title: 'Wildtype source',
          initialValue: _wildtypeSource,
          selectableValues: _WildtypeSource.values,
          displayConversion: (source) => switch (source) {
            _WildtypeSource.fromProject => 'From this project',
            _WildtypeSource.fasta => 'Load a FASTA file',
            _WildtypeSource.paste => 'Paste a sequence',
          },
          onChangedCallback: (source) {
            setState(() {
              _wildtypeSource = source ?? _WildtypeSource.fromProject;
              _setWildtype(null, null);
              _selectedProjectProtein = null;
            });
          },
        ),
      ],
    );
  }

  Widget buildWildtypeSourceInput() {
    switch (_wildtypeSource) {
      case _WildtypeSource.fromProject:
        final proteins = context.watch<ProteinRepository>().databaseToMap().values.toList();
        return BiocentralDiscreteSelection<Protein>(
          title: 'Protein',
          initialValue: _selectedProjectProtein,
          selectableValues: proteins,
          displayConversion: (protein) => '${protein.id} (${protein.sequence.seq.length} aa)',
          onChangedCallback: (protein) {
            setState(() => _selectedProjectProtein = protein);
            _setWildtype(protein?.id, protein?.sequence.seq.toUpperCase());
          },
        );
      case _WildtypeSource.fasta:
        return BiocentralFilePathSelection(
          defaultName: _wildtypeId ?? '/path/to/wildtype.fasta',
          allowedExtensions: const ['fasta', 'faa', 'fa', 'fas', 'fsa'],
          fileSelectedCallback: (xFile, path) {
            if (xFile != null) {
              _loadFastaFile(xFile);
            }
          },
        );
      case _WildtypeSource.paste:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Wildtype sequence',
                hintText: 'MKQQKRLYAR...',
              ),
              onChanged: (value) {
                final sequence = value.trim().toUpperCase();
                _setWildtype(_wildtypeId ?? _campaignName, sequence.isEmpty ? null : sequence);
              },
            ),
          ],
        );
    }
  }

  Widget buildWildtypeSummary() {
    final sequence = _wildtypeSequence;
    if (sequence == null) {
      return Container();
    }
    final error = _wildtypeError;
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(border: Border.all(color: error != null ? Colors.red : Colors.grey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_wildtypeId · ${sequence.length} residues'),
          if (error != null)
            Text(error, style: const TextStyle(color: Colors.red))
          else
            const Text('Standard amino acids only ✓'),
        ],
      ),
    );
  }

  Widget buildGoal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('What are you trying to change?'),
        TextFormField(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'What you measure',
            hintText: 'Residual activity after 60 min at 90 °C',
          ),
          onChanged: (value) => setState(() => _measurementName = value),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Unit',
                  hintText: '%',
                ),
                onChanged: (value) => setState(() => _measurementUnit = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: BiocentralDiscreteSelection<ActiveLearningOptimizationMode>(
                title: 'Direction',
                initialValue: _direction,
                selectableValues: const [
                  ActiveLearningOptimizationMode.MAXIMIZE,
                  ActiveLearningOptimizationMode.MINIMIZE,
                ],
                displayConversion: (mode) =>
                    mode == ActiveLearningOptimizationMode.MAXIMIZE ? 'Higher is better' : 'Lower is better',
                onChangedCallback: (mode) {
                  setState(() => _direction = mode ?? ActiveLearningOptimizationMode.MAXIMIZE);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget buildSeedMeasurements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('What have you already measured?'),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _wildtypeFitnessController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Wildtype ${_measurementUnit.isNotEmpty ? '($_measurementUnit)' : ''}',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        ..._seedRows.map(buildSeedRow),
        TextButton.icon(
          onPressed: () => setState(() => _seedRows.add(_SeedRow())),
          icon: const Icon(Icons.add),
          label: const Text('Add a variant you have data for'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            '${(double.tryParse(_wildtypeFitnessController.text) != null ? 1 : 0) + _seedRows.length} '
            'measurement(s). Enough to start, but early suggestions will be close to random -- '
            'starting from the wildtype alone is fine too.',
          ),
        ),
      ],
    );
  }

  Widget buildSeedRow(_SeedRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: row.substitutionController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Variant',
                hintText: 'A186V',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: row.valueController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Value'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _seedRows.remove(row)),
          ),
        ],
      ),
    );
  }
}

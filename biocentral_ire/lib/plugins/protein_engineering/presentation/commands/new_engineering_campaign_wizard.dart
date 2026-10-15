import 'package:bio_flutter/bio_flutter.dart' show Protein;
import 'package:biocentral/biocentral/bloc/biocentral_sidebar_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/domain/fasta_utils.dart';
import 'package:biocentral/plugins/protein_engineering/domain/mutation_descriptor.dart';
import 'package:biocentral/plugins/protein_engineering/domain/sequence_validation.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/style/engineering_style.dart';
import 'package:biocentral/plugins/proteins/domain/protein_repository.dart';
import 'package:biocentral/sdk/biocentral_sdk.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_file_path_selection.dart';
import 'package:biocentral_api/biocentral_api.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum _WildtypeSource { fromProject, fasta, paste }

class _SeedRow {
  final TextEditingController substitutionController = TextEditingController();
  final TextEditingController valueController = TextEditingController();
}

/// A three-step campaign setup: which protein, what goal, and what's already been measured.
class NewEngineeringCampaignWizard extends StatefulWidget {
  final VoidCallback onLaunched;

  const NewEngineeringCampaignWizard({required this.onLaunched, super.key});

  @override
  State<NewEngineeringCampaignWizard> createState() => _NewEngineeringCampaignWizardState();
}

class _NewEngineeringCampaignWizardState extends State<NewEngineeringCampaignWizard> {
  static const String _defaultEmbedderWireName = 'facebook/esm2_t33_650M_UR50D';
  static const ActiveLearningModelType _defaultModelType = ActiveLearningModelType.GAUSSIAN_PROCESS;
  static const int _defaultSeed = 42;
  static const _stepNames = ['Protein', 'Goal', 'Review'];

  int _step = 0;

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

  bool get _step0Valid => _wildtypeSequence != null && _wildtypeError == null;
  bool get _step1Valid => _measurementName.trim().isNotEmpty;

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

  NewEngineeringCampaignCommand? _collectCommand() {
    final wildtypeSequence = _wildtypeSequence;
    final wildtypeId = _wildtypeId;
    if (wildtypeSequence == null || wildtypeId == null || !_step0Valid || !_step1Valid) {
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

  void _launch() {
    final command = _collectCommand();
    if (command == null) {
      return;
    }
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
    widget.onLaunched();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepIndicator(),
              const SizedBox(height: 28),
              switch (_step) {
                0 => _buildProteinStep(),
                1 => _buildGoalStep(),
                _ => _buildReviewStep(),
              },
              const SizedBox(height: 24),
              const Divider(color: EngineeringStyle.border),
              const SizedBox(height: 16),
              _buildNav(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        for (var i = 0; i < _stepNames.length; i++) ...[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i <= _step ? EngineeringStyle.accent : EngineeringStyle.border,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: i <= _step ? Colors.white : EngineeringStyle.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _stepNames[i],
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: i == _step ? EngineeringStyle.textPrimary : EngineeringStyle.textMuted,
            ),
          ),
          if (i < _stepNames.length - 1) ...[
            const SizedBox(width: 8),
            const Expanded(child: Divider(color: EngineeringStyle.border)),
            const SizedBox(width: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildNav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _step > 0
            ? OutlinedButton(onPressed: () => setState(() => _step--), child: const Text('Back'))
            : const SizedBox.shrink(),
        _step < _stepNames.length - 1
            ? ElevatedButton(
                onPressed: (_step == 0 && !_step0Valid) ? null : () => setState(() => _step++),
                child: const Text('Continue'),
              )
            : ElevatedButton(
                onPressed: _step1Valid ? _launch : null,
                child: const Text('Launch campaign'),
              ),
      ],
    );
  }

  Widget _buildProteinStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Which protein are you engineering?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Paste a sequence, upload a FASTA file, or pick one already in this project.',
          style: TextStyle(fontSize: 13, color: EngineeringStyle.textSecondary),
        ),
        const SizedBox(height: 18),
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
        const SizedBox(height: 14),
        _buildWildtypeSourceInput(),
        const SizedBox(height: 14),
        if (_wildtypeSequence != null) _buildWildtypeSummary(),
      ],
    );
  }

  Widget _buildWildtypeSourceInput() {
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
        return TextFormField(
          maxLines: 4,
          style: const TextStyle(fontFamily: EngineeringStyle.monoFontFamily, fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Wildtype sequence',
            hintText: 'MKQQKRLYAR...',
          ),
          onChanged: (value) {
            final sequence = value.trim().toUpperCase();
            _setWildtype(_wildtypeId ?? _campaignName, sequence.isEmpty ? null : sequence);
          },
        );
    }
  }

  Widget _buildWildtypeSummary() {
    final error = _wildtypeError;
    return Row(
      children: [
        Icon(
          error == null ? Icons.check_circle : Icons.error_outline,
          size: 16,
          color: error == null ? EngineeringStyle.success : EngineeringStyle.danger,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            error ?? '${_wildtypeSequence!.length} residues — standard amino acids only',
            style: TextStyle(fontSize: 13, color: error == null ? EngineeringStyle.success : EngineeringStyle.danger),
          ),
        ),
      ],
    );
  }

  Widget _buildGoalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What are you trying to change?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          "This never leaves your project — it's only used to label results.",
          style: TextStyle(fontSize: 13, color: EngineeringStyle.textSecondary),
        ),
        const SizedBox(height: 18),
        TextFormField(
          initialValue: _campaignName,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Campaign name'),
          onChanged: (value) {
            setState(() => _campaignName = value.trim().isEmpty ? 'Engineering-Campaign' : value.trim());
          },
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'What you measure',
                  hintText: 'Residual activity after 60 min at 90 °C',
                ),
                onChanged: (value) => setState(() => _measurementName = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Unit', hintText: '%'),
                onChanged: (value) => setState(() => _measurementUnit = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        BiocentralDiscreteSelection<ActiveLearningOptimizationMode>(
          title: 'Direction',
          initialValue: _direction,
          selectableValues: const [ActiveLearningOptimizationMode.MAXIMIZE, ActiveLearningOptimizationMode.MINIMIZE],
          displayConversion: (mode) =>
              mode == ActiveLearningOptimizationMode.MAXIMIZE ? 'Higher is better' : 'Lower is better',
          onChangedCallback: (mode) => setState(() => _direction = mode ?? ActiveLearningOptimizationMode.MAXIMIZE),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Review & launch', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'You can add measurements you already have, or start from the wildtype alone.',
          style: TextStyle(fontSize: 13, color: EngineeringStyle.textSecondary),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: EngineeringStyle.cardDecoration,
          child: Column(
            children: [
              _reviewRow('Campaign', _campaignName),
              _reviewRow('Wildtype', '${_wildtypeSequence?.length ?? 0} aa'),
              _reviewRow(
                  'Measuring', _measurementUnit.isEmpty ? _measurementName : '$_measurementName ($_measurementUnit)'),
              _reviewRow(
                'Direction',
                _direction == ActiveLearningOptimizationMode.MAXIMIZE ? 'Higher is better' : 'Lower is better',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _wildtypeFitnessController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Wildtype value (optional)'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        ..._seedRows.map(_buildSeedRow),
        TextButton.icon(
          onPressed: () => setState(() => _seedRows.add(_SeedRow())),
          icon: const Icon(Icons.add),
          label: const Text('Add a variant you have data for'),
        ),
      ],
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: EngineeringStyle.textMuted)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSeedRow(_SeedRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: row.substitutionController,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Variant', hintText: 'A186V'),
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
          IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _seedRows.remove(row))),
        ],
      ),
    );
  }
}

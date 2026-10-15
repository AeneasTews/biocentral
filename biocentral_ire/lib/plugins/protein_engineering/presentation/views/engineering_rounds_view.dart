import 'package:biocentral/biocentral/bloc/biocentral_sidebar_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/domain/round_export.dart';
import 'package:biocentral/plugins/protein_engineering/domain/structure_sequence.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/style/engineering_style.dart' show EngineeringStyle;
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_candidates_grid_view.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_structure_viewer_section.dart';
import 'package:biocentral/sdk/biocentral_sdk.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// One round at a time: its suggested candidates next to the structure viewer, with a
/// round switcher and inline measurement entry across multiple rows at once.
class EngineeringRoundsView extends StatefulWidget {
  final EngineeringCampaign campaign;
  final int initialRoundIndex;

  const EngineeringRoundsView({required this.campaign, required this.initialRoundIndex, super.key});

  @override
  State<EngineeringRoundsView> createState() => _EngineeringRoundsViewState();
}

class _EngineeringRoundsViewState extends State<EngineeringRoundsView> {
  late int _roundIndex = widget.initialRoundIndex;
  StructureCandidate? _selected;

  /// Rows currently being entered, by sequence. Not yet submitted.
  final Map<String, PendingMeasurement> _pending = {};

  /// Rows submitted but not yet accepted via the command log sidebar; their entered value
  /// is fixed and no longer editable.
  final Set<String> _locked = {};

  /// Bumped on every edit/lock action so the grid knows to re-render; never on a keystroke.
  int _editVersion = 0;

  @override
  void didUpdateWidget(EngineeringRoundsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.campaign != widget.campaign) {
      _roundIndex = widget.initialRoundIndex;
      _selected = null;
      _pending.clear();
      _locked.clear();
    }
  }

  Future<void> _openEntryDialog(MeasuredVariant base, {PendingMeasurement? existing}) async {
    final result = await showDialog<PendingMeasurement>(
      context: context,
      builder: (_) => _EnterValueDialog(base: base, existing: existing),
    );
    if (result == null) {
      return;
    }
    setState(() {
      _pending[base.sequence] = result;
      _editVersion++;
    });
  }

  void _cancelEditing(String sequence) {
    setState(() {
      _pending.remove(sequence);
      _editVersion++;
    });
  }

  void _submitPending() {
    final newMeasurements = <MeasuredVariant>[];
    final submittedSequences = <String>[];
    for (final entry in _pending.entries) {
      final pending = entry.value;
      if (!pending.didNotExpress && pending.value == null) {
        continue; // Incomplete; leave it editable rather than submitting a blank value.
      }
      final base = pending.base;
      newMeasurements.add(MeasuredVariant(
        seqId: base.seqId,
        sequence: base.sequence,
        parentSequence: base.parentSequence,
        substitutions: base.substitutions,
        roundFound: base.roundFound,
        fitness: pending.didNotExpress ? null : pending.value,
      ));
      submittedSequences.add(entry.key);
    }
    if (newMeasurements.isEmpty) {
      return;
    }

    context
        .read<BiocentralSideBarBloc>()
        .add(BiocentralSideBarChangeVisibilityEvent(displayMode: BiocentralSideBarDisplayMode.commandLog, force: true));
    context.read<BiocentralCommandBloc>().add(
          BiocentralCommandExecuteEvent(
            command: AddEngineeringMeasurementsCommand(
              engineeringRepository: context.read<EngineeringRepository>(),
              campaign: widget.campaign,
              newMeasurements: newMeasurements,
            ),
            visualizeResult: (log) => BiocentralStatusIndicator(metaData: log.metaData),
            autoAccept: false,
          ),
        );
    setState(() {
      _locked.addAll(submittedSequences);
      _editVersion++;
    });
  }

  Future<void> _exportForBench(EngineeringRound round) async {
    final projectRepository = context.read<BiocentralProjectRepository>();
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export round for the bench',
      fileName: 'round_${round.sentConfig.iteration}_candidates.csv',
    );
    if (savePath == null) {
      return;
    }
    final xFile = XFile(savePath);
    final fileName = xFile.name;
    final dirPath = savePath.substring(0, savePath.length - fileName.length - 1);
    await projectRepository.handleExternalSave(
      fileName: fileName,
      contentFunction: () async => roundCandidatesToCsv(round),
      dirPath: dirPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rounds = widget.campaign.rounds;
    if (rounds.isEmpty) {
      return const Center(child: Text('No rounds run yet.', style: TextStyle(color: EngineeringStyle.textMuted)));
    }
    final roundIndex = _roundIndex.clamp(0, rounds.length - 1);
    final round = rounds[roundIndex];
    final candidates = structureCandidatesForRound(round);
    final submittableCount = _pending.values.where((entry) => entry.didNotExpress || entry.value != null).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: roundIndex > 0 ? () => setState(() => _roundIndex = roundIndex - 1) : null,
              ),
              Text('Round ${round.sentConfig.iteration} of ${rounds.length}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: roundIndex < rounds.length - 1 ? () => setState(() => _roundIndex = roundIndex + 1) : null,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _exportForBench(round),
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Export for the bench'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: EngineeringCandidatesGridView(
                          campaign: widget.campaign,
                          displayedRound: round,
                          selectedSequence: _selected?.sequence,
                          pending: _pending,
                          lockedSequences: _locked,
                          editVersion: _editVersion,
                          onCandidateSelected: (candidate) => setState(() => _selected = candidate),
                          onStartEditing: (base) => _openEntryDialog(base),
                          onEditPending: (entry) => _openEntryDialog(entry.base, existing: entry),
                          onCancelEditing: _cancelEditing,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: submittableCount == 0 ? null : _submitPending,
                          child: Text('Submit $submittableCount measurement(s)'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: EngineeringStructureViewerSection(
                    campaign: widget.campaign,
                    candidates: candidates,
                    selected: _selected,
                    onSelectedChanged: (candidate) => setState(() => _selected = candidate),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Collects a measured value, or a "did not express" flag, for one candidate. Saving only
/// updates the caller's local pending state — it never submits anything.
class _EnterValueDialog extends StatefulWidget {
  final MeasuredVariant base;
  final PendingMeasurement? existing;

  const _EnterValueDialog({required this.base, this.existing});

  @override
  State<_EnterValueDialog> createState() => _EnterValueDialogState();
}

class _EnterValueDialogState extends State<_EnterValueDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.existing?.value?.toString() ?? '');
  late bool _didNotExpress = widget.existing?.didNotExpress ?? false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(_controller.text.trim());
    final canSave = _didNotExpress || value != null;
    return AlertDialog(
      title: const Text('Enter measurement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            enabled: !_didNotExpress,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Measured value'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _didNotExpress,
            onChanged: (checked) => setState(() => _didNotExpress = checked ?? false),
            title: const Text('Did not express'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: canSave
              ? () => Navigator.of(context).pop(
                    PendingMeasurement(base: widget.base, value: value, didNotExpress: _didNotExpress),
                  )
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

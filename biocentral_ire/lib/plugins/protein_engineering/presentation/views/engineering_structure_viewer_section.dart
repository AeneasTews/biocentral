import 'package:bio_flutter/bio_flutter.dart';
import 'package:biocentral/plugins/protein_engineering/domain/structure_sequence.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/commands/upload_structure_button.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/style/engineering_style.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_discrete_selection.dart';
import 'package:flutter/material.dart';

/// Shows the campaign's wildtype structure with [selected]'s mutations highlighted.
/// Stays empty until a structure matching the campaign's wildtype has been uploaded.
class EngineeringStructureViewerSection extends StatefulWidget {
  final EngineeringCampaign campaign;
  final List<StructureCandidate> candidates;
  final StructureCandidate? selected;
  final ValueChanged<StructureCandidate?> onSelectedChanged;

  const EngineeringStructureViewerSection({
    required this.campaign,
    required this.candidates,
    required this.selected,
    required this.onSelectedChanged,
    super.key,
  });

  @override
  State<EngineeringStructureViewerSection> createState() => _EngineeringStructureViewerSectionState();
}

class _EngineeringStructureViewerSectionState extends State<EngineeringStructureViewerSection> {
  String? _parsedFor;
  WildtypeStructureMatch? _match;
  bool _parsing = false;

  @override
  void initState() {
    super.initState();
    final mmcif = widget.campaign.wildtypeStructureMmcif;
    if (mmcif != null) {
      _ensureParsed(mmcif);
    }
  }

  @override
  void didUpdateWidget(EngineeringStructureViewerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mmcif = widget.campaign.wildtypeStructureMmcif;
    if (mmcif != null && mmcif != _parsedFor) {
      _ensureParsed(mmcif);
    }
  }

  Future<void> _ensureParsed(String mmcif) async {
    if (mmcif == _parsedFor || _parsing) {
      return;
    }
    _parsing = true;
    try {
      final result = await MmcifParser.parse(mmcif);
      if (!mounted) {
        return;
      }
      setState(() {
        _parsedFor = mmcif;
        _match = matchWildtypeStructure(result.structure, widget.campaign.wildtypeSequence);
      });
    } finally {
      _parsing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mmcif = widget.campaign.wildtypeStructureMmcif;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: EngineeringStyle.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Structure', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              UploadStructureButton(campaign: widget.campaign, hasStructure: mmcif != null),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: mmcif == null
                ? _placeholder('Upload a structure of the wildtype to view mutations in 3D.')
                : (mmcif != _parsedFor || _match == null)
                    ? _placeholder(null)
                    : _buildViewer(_match!),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(String? message) {
    return Center(
      child: message == null
          ? const CircularProgressIndicator()
          : Text(message, style: const TextStyle(color: EngineeringStyle.textSecondary)),
    );
  }

  Widget _buildViewer(WildtypeStructureMatch match) {
    final selected = widget.selected;
    final highlights = selected == null
        ? const <ResidueKey, Color>{}
        : highlightsForCandidate(
            match: match,
            wildtypeSequence: widget.campaign.wildtypeSequence,
            candidateSequence: selected.sequence,
            color: EngineeringStyle.mutationColor,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ProteinViewer(
            structure: match.structure,
            highlights: highlights,
            style: EngineeringStyle.cartoonStyle,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: BiocentralDiscreteSelection<StructureCandidate?>(
                title: 'Variant',
                initialValue: selected,
                selectableValues: [null, ...widget.candidates],
                displayConversion: (candidate) => candidate?.label ?? 'Wildtype',
                onChangedCallback: widget.onSelectedChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: EngineeringStyle.mutationColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              selected == null ? 'Mutated residue' : 'Mutated residue — ${selected.label}',
              style: const TextStyle(fontSize: 12, color: EngineeringStyle.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

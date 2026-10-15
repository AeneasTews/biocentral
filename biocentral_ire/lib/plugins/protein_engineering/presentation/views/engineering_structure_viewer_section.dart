import 'package:bio_flutter/bio_flutter.dart';
import 'package:biocentral/plugins/protein_engineering/domain/structure_sequence.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/commands/upload_wildtype_structure_command_display.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_discrete_selection.dart';
import 'package:flutter/material.dart';

/// Shows the campaign's wildtype structure with the selected candidate's mutations highlighted,
/// underneath an upload/replace control. The viewer stays hidden until a matching structure has
/// been uploaded for this campaign.
class EngineeringStructureViewerSection extends StatefulWidget {
  final EngineeringCampaign campaign;
  final List<StructureCandidate> candidates;

  const EngineeringStructureViewerSection({required this.campaign, required this.candidates, super.key});

  @override
  State<EngineeringStructureViewerSection> createState() => _EngineeringStructureViewerSectionState();
}

class _EngineeringStructureViewerSectionState extends State<EngineeringStructureViewerSection> {
  static const Color _mutationColor = Color(0xFF8E24AA);

  String? _parsedFor;
  WildtypeStructureMatch? _match;
  bool _parsing = false;
  StructureCandidate? _selected;

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
    if (!widget.candidates.any((candidate) => candidate.sequence == _selected?.sequence)) {
      _selected = null;
    }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Text('Structure', style: TextStyle(fontWeight: FontWeight.bold)),
        if (mmcif == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Upload a structure of the wildtype to view mutations in 3D.'),
          )
        else if (mmcif != _parsedFor || _match == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          buildViewer(_match!),
        UploadWildtypeStructureCommandDisplay(campaign: widget.campaign),
      ],
    );
  }

  Widget buildViewer(WildtypeStructureMatch match) {
    final selected = _selected;
    final highlights = selected == null
        ? const <ResidueKey, Color>{}
        : highlightsForCandidate(
            match: match,
            wildtypeSequence: widget.campaign.wildtypeSequence,
            candidateSequence: selected.sequence,
            color: _mutationColor,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BiocentralDiscreteSelection<StructureCandidate?>(
          title: 'Variant',
          initialValue: _selected,
          selectableValues: [null, ...widget.candidates],
          displayConversion: (candidate) => candidate?.label ?? 'Wildtype',
          onChangedCallback: (candidate) => setState(() => _selected = candidate),
        ),
        SizedBox(
          height: 420,
          child: ProteinViewer(
            structure: match.structure,
            highlights: highlights,
            style: CartoonStyle(
              helixColor: const Color(0xFF9E793D),
              sheetColor: Colors.green.shade600,
              outlineColor: Colors.black,
              outlineThickness: 0.12,
              pencilTexture: true,
            ),
          ),
        ),
      ],
    );
  }
}

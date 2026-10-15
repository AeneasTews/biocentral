import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/bloc/biocentral_command_availability.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_command_widget.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_file_path_selection.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_status_indicator.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UploadWildtypeStructureCommandDisplay extends StatefulWidget {
  final EngineeringCampaign campaign;

  const UploadWildtypeStructureCommandDisplay({required this.campaign, super.key});

  @override
  State<UploadWildtypeStructureCommandDisplay> createState() => _UploadWildtypeStructureCommandDisplayState();
}

class _UploadWildtypeStructureCommandDisplayState extends State<UploadWildtypeStructureCommandDisplay> {
  String? _fileName;
  String? _mmcifContent;
  String? _readError;

  Future<void> _loadFile(XFile xFile) async {
    try {
      final content = await xFile.readAsString();
      setState(() {
        _fileName = xFile.name;
        _mmcifContent = content;
        _readError = null;
      });
    } catch (e) {
      setState(() {
        _fileName = null;
        _mmcifContent = null;
        _readError = 'Could not read structure file: $e';
      });
    }
  }

  UploadWildtypeStructureCommand? collectCommand() {
    final content = _mmcifContent;
    if (content == null) {
      return null;
    }
    return UploadWildtypeStructureCommand(
      engineeringRepository: context.read<EngineeringRepository>(),
      campaign: widget.campaign,
      mmcifContent: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStructure = widget.campaign.wildtypeStructureMmcif != null;
    return BiocentralCommandWidget(
      icon: const Icon(Icons.view_in_ar_outlined),
      name: hasStructure ? 'Replace wildtype structure' : 'Upload wildtype structure',
      description: 'Load an mmCIF structure of the wildtype to view mutations on the 3D structure. '
          "The structure's sequence must match the campaign's wildtype sequence exactly.",
      executeButtonLabel: 'Use structure',
      parameterSelection: buildParameterSelection,
      collectCommand: collectCommand,
      visualizeResult: (log) => BiocentralStatusIndicator(metaData: log.metaData),
      commandAvailability: BiocentralCommandAvailability.always(),
    );
  }

  Widget buildParameterSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BiocentralFilePathSelection(
          defaultName: _fileName ?? '/path/to/structure.cif',
          allowedExtensions: const ['cif', 'mmcif'],
          fileSelectedCallback: (xFile, path) {
            if (xFile != null) {
              _loadFile(xFile);
            }
          },
        ),
        if (_readError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(_readError!, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }
}

import 'package:biocentral/biocentral/bloc/biocentral_sidebar_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/biocentral_sdk.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Picks an mmCIF file and submits it as the campaign's wildtype structure.
/// Errors (e.g. a sequence mismatch) surface through the usual command log sidebar.
class UploadStructureButton extends StatelessWidget {
  final EngineeringCampaign campaign;
  final bool hasStructure;

  const UploadStructureButton({required this.campaign, required this.hasStructure, super.key});

  Future<void> _pickAndUpload(BuildContext context) async {
    final result = await FilePicker.platform
        .pickFiles(allowedExtensions: const ['cif', 'mmcif'], type: FileType.custom, withData: kIsWeb);
    if (result == null) {
      return;
    }
    final content = await result.xFiles.single.readAsString();
    if (!context.mounted) {
      return;
    }
    final command = UploadWildtypeStructureCommand(
      engineeringRepository: context.read<EngineeringRepository>(),
      campaign: campaign,
      mmcifContent: content,
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
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: hasStructure ? 'Replace structure' : 'Upload structure',
      icon: const Icon(Icons.view_in_ar_outlined, size: 18),
      onPressed: () => _pickAndUpload(context),
    );
  }
}

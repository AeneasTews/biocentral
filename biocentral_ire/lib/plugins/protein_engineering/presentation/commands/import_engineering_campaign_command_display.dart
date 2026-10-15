import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_hub_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/biocentral_sdk.dart';
import 'package:biocentral/sdk/bloc/biocentral_command_availability.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_command_widget.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_file_path_selection.dart';
import 'package:biocentral/sdk/util/widget_util.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ImportEngineeringCampaignCommandDisplay extends StatefulWidget {
  const ImportEngineeringCampaignCommandDisplay({super.key});

  @override
  State<ImportEngineeringCampaignCommandDisplay> createState() => _ImportEngineeringCampaignCommandDisplayState();
}

class _ImportEngineeringCampaignCommandDisplayState extends State<ImportEngineeringCampaignCommandDisplay> {
  XFile? _selectedFile;

  LoadEngineeringCampaignCommand? collectCommand() {
    if (_selectedFile == null) return null;
    return LoadEngineeringCampaignCommand(
      projectRepository: context.read<BiocentralProjectRepository>(),
      engineeringRepository: context.read<EngineeringRepository>(),
      campaignFile: _selectedFile!,
      importMode: DatabaseImportMode.overwrite,
    );
  }

  Widget _buildImportResult(BiocentralCommandLog log, List<EngineeringCampaign> existingCampaigns) {
    final loaded = log.result?.result;
    if (loaded == null || loaded is! List<EngineeringCampaign>) {
      return BiocentralStatusIndicator(metaData: log.metaData);
    }

    final existingNames = {for (final campaign in existingCampaigns) campaign.internalName()};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BiocentralStatusIndicator(metaData: log.metaData),
        const SizedBox(height: 8),
        ...loaded.map((campaign) {
          final conflicts = existingNames.contains(campaign.internalName());
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(
                conflicts ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: conflicts ? BiocentralStyle.alWarningColor : BiocentralStyle.alSuccessColor,
              ),
              title: Text(campaign.config.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${campaign.rounds.length} round(s); wildtype: ${campaign.wildtypeId}'),
                  const SizedBox(height: 2),
                  Text(
                    conflicts
                        ? 'A campaign with this name already exists and will be overwritten if you proceed!'
                        : 'Campaign can be added without issues.',
                    style: TextStyle(
                        color: conflicts ? BiocentralStyle.alWarningTextColor : BiocentralStyle.alSuccessTextColor,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
              isThreeLine: true,
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EngineeringHubBloc, EngineeringHubState>(
      builder: (context, state) {
        final existingCampaigns = state.campaigns;
        return BiocentralCommandWidget(
          icon: const Icon(Icons.file_open),
          name: 'Import campaign',
          description: 'Load a previously exported campaign from a JSON file',
          executeButtonLabel: 'Import',
          parameterSelection: buildParameterSelection,
          collectCommand: collectCommand,
          visualizeResult: (log) => _buildImportResult(log, existingCampaigns),
          commandAvailability: BiocentralCommandAvailability.always(),
        );
      },
    );
  }

  Widget buildParameterSelection() {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        children: [
          BiocentralFilePathSelection(
            defaultName: _selectedFile?.name ?? 'Select campaign JSON file',
            allowedExtensions: const ['json'],
            fileSelectedCallback: (xFile, _) => setState(() {
              _selectedFile = xFile;
            }),
          ),
        ].withPadding(const Padding(padding: EdgeInsets.all(8.0))),
      ),
    );
  }
}

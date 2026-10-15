import 'package:biocentral/plugins/protein_engineering/bloc/engineering_commands.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_hub_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/sdk/biocentral_sdk.dart';
import 'package:biocentral/sdk/bloc/biocentral_command_availability.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_command_widget.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_file_path_selection.dart';
import 'package:biocentral/sdk/util/widget_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ExportEngineeringCampaignCommandDisplay extends StatefulWidget {
  const ExportEngineeringCampaignCommandDisplay({super.key});

  @override
  State<ExportEngineeringCampaignCommandDisplay> createState() => _ExportEngineeringCampaignCommandDisplayState();
}

class _ExportEngineeringCampaignCommandDisplayState extends State<ExportEngineeringCampaignCommandDisplay> {
  EngineeringCampaign? _selectedCampaign;
  String? _exportPath;

  ExportEngineeringCampaignCommand? collectCommand() {
    if (_selectedCampaign != null && _exportPath != null) {
      return ExportEngineeringCampaignCommand(
        projectRepository: context.read<BiocentralProjectRepository>(),
        campaign: _selectedCampaign!,
        filePath: _exportPath!,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<EngineeringHubBloc, EngineeringHubState>(
      listenWhen: (previous, current) => previous.selectedCampaign != current.selectedCampaign,
      listener: (context, state) {
        setState(() {
          _selectedCampaign = state.selectedCampaign;
          _exportPath = null;
        });
      },
      builder: (context, state) {
        final availability = BiocentralCommandAvailability(
          available: state.campaigns.isNotEmpty,
          unavailableMessage: 'No campaigns available to export!',
        );
        return BiocentralCommandWidget(
          icon: const Icon(Icons.save),
          name: 'Export campaign',
          description: 'Save a campaign to a JSON file',
          executeButtonLabel: 'Export',
          parameterSelection: () => buildParameterSelection(state.campaigns),
          collectCommand: collectCommand,
          visualizeResult: BiocentralCommandWidget.visualizeDatabaseResult,
          commandAvailability: availability,
          alwaysAutoAccept: true,
        );
      },
    );
  }

  Widget buildParameterSelection(List<EngineeringCampaign> campaigns) {
    final defaultFileName = 'campaign_${_selectedCampaign?.config.name ?? 'export'}.json';
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        children: [
          BiocentralDiscreteSelection<EngineeringCampaign>(
            title: 'Campaign to export',
            selectableValues: campaigns,
            initialValue: _selectedCampaign,
            displayConversion: (c) => c.config.name,
            onChangedCallback: (EngineeringCampaign? selected) {
              setState(() {
                _selectedCampaign = selected;
                _exportPath = null;
              });
            },
          ),
          BiocentralFilePathSelection(
            defaultName: _exportPath ?? defaultFileName,
            allowedExtensions: const ['json'],
            fileSelectedCallback: (_, path) => setState(() {
              _exportPath = path;
            }),
            pickForExport: true,
          ),
        ].withPadding(const Padding(padding: EdgeInsets.all(8.0))),
      ),
    );
  }
}

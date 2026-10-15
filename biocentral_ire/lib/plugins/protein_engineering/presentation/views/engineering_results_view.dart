import 'package:biocentral/plugins/protein_engineering/bloc/engineering_hub_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/domain/round_export.dart';
import 'package:biocentral/plugins/protein_engineering/domain/structure_sequence.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_candidates_grid_view.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_progress_view.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_structure_viewer_section.dart';
import 'package:biocentral/sdk/domain/biocentral_project_repository.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_discrete_selection.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EngineeringResultsView extends StatefulWidget {
  const EngineeringResultsView({super.key});

  @override
  State<EngineeringResultsView> createState() => _EngineeringResultsViewState();
}

class _EngineeringResultsViewState extends State<EngineeringResultsView>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  int _selectedRoundIndex = 0;
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
    final length = context.read<EngineeringHubBloc>().state.selectedCampaign?.rounds.length ?? 0;
    _selectedRoundIndex = length > 0 ? length - 1 : 0;
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocConsumer<EngineeringHubBloc, EngineeringHubState>(
      listenWhen: (previous, current) =>
          previous.selectedCampaign?.internalName() != current.selectedCampaign?.internalName() ||
          previous.selectedCampaignRoundCount != current.selectedCampaignRoundCount,
      listener: (context, state) {
        final length = state.selectedCampaign?.rounds.length ?? 0;
        setState(() => _selectedRoundIndex = length > 0 ? length - 1 : 0);
      },
      builder: (context, hubState) {
        return Scaffold(body: buildContent(hubState));
      },
    );
  }

  Widget buildContent(EngineeringHubState hubState) {
    if (hubState.campaigns.isEmpty) {
      return const Center(child: Text('No protein engineering campaigns yet.'));
    }
    final campaign = hubState.selectedCampaign;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: BiocentralDiscreteSelection<EngineeringCampaign>(
            title: 'Select Campaign',
            initialValue: campaign,
            selectableValues: hubState.campaigns,
            displayConversion: (c) => c.config.name,
            onChangedCallback: (selected) =>
                context.read<EngineeringHubBloc>().add(EngineeringHubSelectCampaignEvent(selected)),
          ),
        ),
        if (campaign != null) ...[
          TabBar(
            controller: _subTabController,
            labelColor: Theme.of(context).colorScheme.onSurface,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            tabs: const [
              Tab(icon: Icon(Icons.timeline), text: 'Current Round'),
              Tab(icon: Icon(Icons.assessment), text: 'All Rounds'),
              Tab(icon: Icon(Icons.show_chart), text: 'Progress'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _subTabController,
              children: [
                SingleChildScrollView(child: buildRoundView(campaign)),
                SingleChildScrollView(child: buildAllRoundsView(campaign)),
                EngineeringProgressView(campaign: campaign),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget buildRoundView(EngineeringCampaign campaign) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * 0.9;
        final totalRounds = campaign.rounds.length;
        if (totalRounds == 0) {
          return const Center(child: Text('No rounds run yet.'));
        }
        final round = campaign.rounds[_selectedRoundIndex];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_left),
                  onPressed: _selectedRoundIndex > 0 ? () => setState(() => _selectedRoundIndex--) : null,
                ),
                Text('Round ${round.sentConfig.iteration}'),
                IconButton(
                  icon: const Icon(Icons.arrow_right),
                  onPressed: _selectedRoundIndex < totalRounds - 1 ? () => setState(() => _selectedRoundIndex++) : null,
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: () => _exportRoundForBench(round),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export for the bench'),
                ),
              ],
            ),
            SizedBox(
              width: width,
              height: width * 0.5,
              child: EngineeringCandidatesGridView(campaign: campaign, displayedRound: round),
            ),
            SizedBox(
              width: width,
              child: EngineeringStructureViewerSection(
                campaign: campaign,
                candidates: structureCandidatesForRound(round),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportRoundForBench(EngineeringRound round) async {
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

  Widget buildAllRoundsView(EngineeringCampaign campaign) {
    if (campaign.rounds.isEmpty) {
      return const Center(child: Text('No rounds run yet.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * 0.9;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width,
              height: width * 0.6,
              child: EngineeringCandidatesGridView(campaign: campaign, displayedRound: null),
            ),
            SizedBox(
              width: width,
              child: EngineeringStructureViewerSection(
                campaign: campaign,
                candidates: structureCandidatesForAllRounds(campaign.rounds),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

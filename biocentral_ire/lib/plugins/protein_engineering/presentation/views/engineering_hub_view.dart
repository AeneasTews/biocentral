import 'package:biocentral/biocentral/bloc/biocentral_sidebar_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/bloc/engineering_hub_bloc.dart';
import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/commands/export_engineering_campaign_command_display.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/commands/import_engineering_campaign_command_display.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/commands/new_engineering_campaign_wizard.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/style/engineering_style.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_history_view.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_overview_view.dart';
import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_rounds_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum _Section { overview, rounds, history, newCampaign }

enum _DataMenuAction { export, import }

/// The plugin's top-level shell: a campaign/section sidebar next to the active section's content.
class EngineeringHubView extends StatefulWidget {
  const EngineeringHubView({super.key});

  @override
  State<EngineeringHubView> createState() => _EngineeringHubViewState();
}

class _EngineeringHubViewState extends State<EngineeringHubView> {
  _Section _section = _Section.overview;
  int? _roundIndexOverride;

  void _selectCampaign(BuildContext context, EngineeringCampaign campaign) {
    context.read<EngineeringHubBloc>().add(EngineeringHubSelectCampaignEvent(campaign));
    setState(() {
      _section = _Section.overview;
      _roundIndexOverride = null;
    });
  }

  void _showDataDialog(BuildContext context, _DataMenuAction action) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: switch (action) {
            _DataMenuAction.export => const ExportEngineeringCampaignCommandDisplay(),
            _DataMenuAction.import => const ImportEngineeringCampaignCommandDisplay(),
          },
        ),
      ),
    );
  }

  void _openRound(int index) {
    setState(() {
      _section = _Section.rounds;
      _roundIndexOverride = index;
    });
  }

  Future<void> _confirmDeleteCampaign(EngineeringCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete campaign?'),
        content: Text('"${campaign.config.name}" and all of its rounds and measurements will be deleted permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    context.read<EngineeringRepository>().removeCampaign(campaign.internalName());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EngineeringHubBloc, EngineeringHubState>(
      builder: (context, state) {
        return Container(
          color: EngineeringStyle.background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidebar(context, state),
              Expanded(child: _buildContent(state)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context, EngineeringHubState state) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: EngineeringStyle.surface,
        border: Border(right: BorderSide(color: EngineeringStyle.border)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Row(
                  children: [
                    Icon(Icons.science_outlined, size: 20, color: EngineeringStyle.accent),
                    SizedBox(width: 8),
                    Text('Engineering', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => _section = _Section.newCampaign),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New campaign'),
                  ),
                ),
                const SizedBox(height: 18),
                _sectionLabel('CAMPAIGNS'),
                for (final campaign in state.campaigns)
                  _sidebarItem(
                    label: campaign.config.name,
                    leadingDot: campaign == state.selectedCampaign ? EngineeringStyle.accent : EngineeringStyle.border,
                    selected: false,
                    onTap: () => _selectCampaign(context, campaign),
                    onDelete: () => _confirmDeleteCampaign(campaign),
                  ),
                if (state.selectedCampaign != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: EngineeringStyle.border, height: 1),
                  ),
                  _sectionLabel('THIS CAMPAIGN'),
                  _sidebarItem(
                    label: 'Overview',
                    selected: _section == _Section.overview,
                    onTap: () => setState(() => _section = _Section.overview),
                  ),
                  _sidebarItem(
                    label: 'Rounds',
                    selected: _section == _Section.rounds,
                    onTap: () => setState(() {
                      _section = _Section.rounds;
                      _roundIndexOverride = null;
                    }),
                  ),
                  _sidebarItem(
                    label: 'History',
                    selected: _section == _Section.history,
                    onTap: () => setState(() => _section = _Section.history),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => context.read<BiocentralSideBarBloc>().add(
                        BiocentralSideBarChangeVisibilityEvent(displayMode: BiocentralSideBarDisplayMode.commandLog),
                      ),
                  icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
                  label: const Text('Activity', style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                PopupMenuButton<_DataMenuAction>(
                  icon: const Icon(Icons.more_horiz, size: 18),
                  tooltip: 'Import or export campaigns',
                  onSelected: (action) => _showDataDialog(context, action),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: _DataMenuAction.export, child: Text('Export campaign…')),
                    PopupMenuItem(value: _DataMenuAction.import, child: Text('Import campaign…')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: EngineeringStyle.textMuted),
      ),
    );
  }

  Widget _sidebarItem({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? leadingDot,
    VoidCallback? onDelete,
  }) {
    return Material(
      color: selected ? EngineeringStyle.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              if (leadingDot != null) ...[
                Container(width: 7, height: 7, decoration: BoxDecoration(color: leadingDot, shape: BoxShape.circle)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? EngineeringStyle.accent : EngineeringStyle.textPrimary,
                  ),
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Delete campaign',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(EngineeringHubState state) {
    if (_section == _Section.newCampaign) {
      return NewEngineeringCampaignWizard(onLaunched: () => setState(() => _section = _Section.overview));
    }
    final campaign = state.selectedCampaign;
    if (campaign == null) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: () => setState(() => _section = _Section.newCampaign),
          icon: const Icon(Icons.add),
          label: const Text('Start your first campaign'),
        ),
      );
    }
    switch (_section) {
      case _Section.overview:
        return EngineeringOverviewView(
          campaign: campaign,
          onOpenRound: _openRound,
          onOpenHistory: () => setState(() => _section = _Section.history),
        );
      case _Section.rounds:
        return EngineeringRoundsView(
          key: ValueKey(campaign.internalName()),
          campaign: campaign,
          initialRoundIndex: _roundIndexOverride ?? (campaign.rounds.isEmpty ? 0 : campaign.rounds.length - 1),
        );
      case _Section.history:
        return EngineeringHistoryView(campaign: campaign);
      case _Section.newCampaign:
        return NewEngineeringCampaignWizard(onLaunched: () => setState(() => _section = _Section.overview));
    }
  }
}

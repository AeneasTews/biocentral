import 'package:biocentral/plugins/protein_engineering/presentation/views/engineering_results_view.dart';
import 'package:biocentral/sdk/presentation/widgets/biocentral_command_view.dart';
import 'package:biocentral/sdk/util/size_config.dart';
import 'package:flutter/material.dart';

class EngineeringHubView extends StatefulWidget {
  final List<Widget> commandWidgets;

  const EngineeringHubView({required this.commandWidgets, super.key});

  @override
  State<EngineeringHubView> createState() => _EngineeringHubViewState();
}

class _EngineeringHubViewState extends State<EngineeringHubView> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: TabBar(
                labelColor: Theme.of(context).colorScheme.onSurface,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                tabs: const [
                  Tab(icon: Icon(Icons.list_alt), text: 'Campaigns'),
                  Tab(icon: Icon(Icons.insert_chart), text: 'Commands'),
                ],
              ),
            ),
            SizedBox(height: SizeConfig.safeBlockVertical(context) * 2),
            Flexible(
              flex: 5,
              child: TabBarView(
                children: [
                  const EngineeringResultsView(),
                  BiocentralCommandView(commandWidgets: widget.commandWidgets),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

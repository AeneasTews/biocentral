import 'package:biocentral/plugins/protein_engineering/domain/engineering_repository.dart';
import 'package:biocentral/plugins/protein_engineering/model/engineering_campaign.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

sealed class EngineeringHubEvent {}

final class _EngineeringHubLoadInternalEvent extends EngineeringHubEvent {
  final List<EngineeringCampaign> campaigns;

  _EngineeringHubLoadInternalEvent({required this.campaigns});
}

final class EngineeringHubSelectCampaignEvent extends EngineeringHubEvent {
  final EngineeringCampaign? campaign;

  EngineeringHubSelectCampaignEvent(this.campaign);
}

final class EngineeringHubState extends Equatable {
  final List<EngineeringCampaign> campaigns;
  final EngineeringCampaign? selectedCampaign;
  final int _selectedCampaignRoundCount;

  EngineeringHubState({
    required this.campaigns,
    this.selectedCampaign,
  }) : _selectedCampaignRoundCount = selectedCampaign?.rounds.length ?? 0;

  EngineeringHubState.initial()
      : campaigns = const [],
        selectedCampaign = null,
        _selectedCampaignRoundCount = 0;

  int get selectedCampaignRoundCount => _selectedCampaignRoundCount;

  @override
  List<Object?> get props => [campaigns, selectedCampaign, _selectedCampaignRoundCount];
}

class EngineeringHubBloc extends Bloc<EngineeringHubEvent, EngineeringHubState> {
  final EngineeringRepository _engineeringRepository;

  EngineeringHubBloc(this._engineeringRepository) : super(EngineeringHubState(campaigns: const [])) {
    on<_EngineeringHubLoadInternalEvent>((event, emit) async {
      if (event.campaigns.isEmpty) {
        emit(EngineeringHubState.initial());
        return;
      }

      final selectedName = state.selectedCampaign?.internalName();
      final selected = selectedName != null
          ? event.campaigns.firstWhereOrNull((c) => c.internalName() == selectedName) ?? event.campaigns.first
          : event.campaigns.first;

      emit(EngineeringHubState(campaigns: event.campaigns, selectedCampaign: selected));
    });

    on<EngineeringHubSelectCampaignEvent>((event, emit) {
      emit(EngineeringHubState(campaigns: state.campaigns, selectedCampaign: event.campaign));
    });

    _setupSubscriptions();
  }

  void _setupSubscriptions() {
    _engineeringRepository.databaseStream.listen((campaigns) {
      add(_EngineeringHubLoadInternalEvent(campaigns: campaigns));
    });
  }
}

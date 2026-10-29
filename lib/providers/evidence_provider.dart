import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/evidence_item.dart';
import 'package:aerial_eye/services/evidence_storage_service.dart';

class EvidenceState {
  final List<EvidenceItem> items;
  final bool isLoading;
  final DetectionType? filterType;
  final EvidenceMediaType? filterMediaType;
  final String? filterMissionId;

  const EvidenceState({
    required this.items,
    this.isLoading = false,
    this.filterType,
    this.filterMediaType,
    this.filterMissionId,
  });

  List<EvidenceItem> get filteredItems {
    return items.where((item) {
      if (filterMediaType != null && item.mediaType != filterMediaType) {
        return false;
      }
      if (filterType != null && item.detectionType != filterType) {
        return false;
      }
      if (filterMissionId != null &&
          filterMissionId != 'ALL' &&
          item.missionId != filterMissionId) {
        return false;
      }
      return true;
    }).toList();
  }

  List<EvidenceItem> get photos =>
      items.where((e) => e.mediaType == EvidenceMediaType.photo).toList();

  List<EvidenceItem> get videos =>
      items.where((e) => e.mediaType == EvidenceMediaType.video).toList();

  Map<DetectionType, int> get countsByClass {
    final map = <DetectionType, int>{
      DetectionType.person: 0,
      DetectionType.animal: 0,
      DetectionType.pothole: 0,
      DetectionType.roadCrack: 0,
      DetectionType.waste: 0,
    };
    for (final item in items) {
      if (item.detectionType != null && map.containsKey(item.detectionType!)) {
        map[item.detectionType!] = (map[item.detectionType!] ?? 0) + 1;
      }
    }
    return map;
  }

  EvidenceState copyWith({
    List<EvidenceItem>? items,
    bool? isLoading,
    DetectionType? filterType,
    bool clearTypeFilter = false,
    EvidenceMediaType? filterMediaType,
    bool clearMediaFilter = false,
    String? filterMissionId,
    bool clearMissionFilter = false,
  }) {
    return EvidenceState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      filterType: clearTypeFilter ? null : (filterType ?? this.filterType),
      filterMediaType: clearMediaFilter
          ? null
          : (filterMediaType ?? this.filterMediaType),
      filterMissionId: clearMissionFilter
          ? null
          : (filterMissionId ?? this.filterMissionId),
    );
  }
}

class EvidenceNotifier extends StateNotifier<EvidenceState> {
  EvidenceNotifier() : super(const EvidenceState(items: [], isLoading: true)) {
    loadEvidence();
  }

  Future<void> loadEvidence() async {
    state = state.copyWith(isLoading: true);
    try {
      final loaded = await EvidenceStorageService.loadAllEvidence();
      state = state.copyWith(items: loaded, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  void addEvidence(EvidenceItem item) {
    if (state.items.any((e) => e.id == item.id)) return;
    state = state.copyWith(items: [item, ...state.items]);
  }

  Future<void> deleteEvidence(String id) async {
    final updated = state.items.where((e) => e.id != id).toList();
    state = state.copyWith(items: updated);
    await EvidenceStorageService.deleteEvidence(id);
  }

  void setFilterType(DetectionType? type) {
    if (type == null) {
      state = state.copyWith(clearTypeFilter: true);
    } else {
      state = state.copyWith(filterType: type);
    }
  }

  void setFilterMediaType(EvidenceMediaType? mediaType) {
    if (mediaType == null) {
      state = state.copyWith(clearMediaFilter: true);
    } else {
      state = state.copyWith(filterMediaType: mediaType);
    }
  }

  void setFilterMissionId(String? missionId) {
    if (missionId == null || missionId == 'ALL') {
      state = state.copyWith(clearMissionFilter: true);
    } else {
      state = state.copyWith(filterMissionId: missionId);
    }
  }
}

final evidenceProvider = StateNotifierProvider<EvidenceNotifier, EvidenceState>(
  (ref) {
    return EvidenceNotifier();
  },
);

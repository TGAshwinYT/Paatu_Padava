import '../domain/models/track_entity.dart';

/// Unified Song model alias pointing directly to TrackEntity.
/// Deprecated: Prefer importing `package:paatupadava/domain/models/track_entity.dart` directly
/// to complete the Clean Architecture transition.
@Deprecated('Import domain/models/track_entity.dart directly')
typedef Song = TrackEntity;

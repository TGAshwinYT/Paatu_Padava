import '../domain/models/track_entity.dart';

/// Unified Song model alias pointing directly to TrackEntity.
/// Eliminates model duality across Paatu Padava while preserving 100% backward compatibility.
typedef Song = TrackEntity;

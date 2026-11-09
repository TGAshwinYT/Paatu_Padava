import 'package:flutter/material.dart';

/// Available real-time mood/vibe lenses for the Up Next queue.
/// Inspired by YouTube Music's Up Next mood tuners and Spotify's smart blend.
enum QueueTunerMode {
  /// Default balanced mix of familiar favorites and contextual recommendations.
  mix,

  /// Focuses strictly on songs and artists the user already knows, likes, or frequently plays.
  familiar,

  /// Strictly excludes played history and favorites to explore fresh, unplayed music gems.
  discover,

  /// Clustered around the active song's Music Director / Composer universe (e.g., Rahman, Anirudh).
  composer,
}

extension QueueTunerModeDetails on QueueTunerMode {
  String get label {
    switch (this) {
      case QueueTunerMode.mix:
        return 'Mix';
      case QueueTunerMode.familiar:
        return 'Familiar';
      case QueueTunerMode.discover:
        return 'Discover';
      case QueueTunerMode.composer:
        return 'Composer';
    }
  }

  IconData get icon {
    switch (this) {
      case QueueTunerMode.mix:
        return Icons.auto_awesome_rounded;
      case QueueTunerMode.familiar:
        return Icons.repeat_rounded;
      case QueueTunerMode.discover:
        return Icons.explore_rounded;
      case QueueTunerMode.composer:
        return Icons.music_note_rounded;
    }
  }

  String get tooltip {
    switch (this) {
      case QueueTunerMode.mix:
        return 'Balanced Mix: Blend of hits and recommendations';
      case QueueTunerMode.familiar:
        return 'Familiar: Songs and artists you already love';
      case QueueTunerMode.discover:
        return 'Discover: Fresh tracks you haven\'t heard yet';
      case QueueTunerMode.composer:
        return 'Composer Flow: Music from the same director/composer';
    }
  }
}


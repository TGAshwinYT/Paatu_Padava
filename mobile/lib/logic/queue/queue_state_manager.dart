import 'package:just_audio/just_audio.dart';
import '../../domain/models/track_entity.dart';
import 'smart_shuffle_permutator.dart';

/// Coordinates the Two-Tier Queue State (Context Queue + Explicit User Queue)
/// and Playback History, decoupled from low-level audio stream playback.
class QueueStateManager {
  final SmartShufflePermutator shufflePermutator;

  // 1. Context Queue: persistent album / playlist context
  final List<TrackEntity> contextQueue = [];
  final List<int> contextShuffleIndices = [];
  int contextIndex = -1;
  bool isShuffleEnabled = false;

  // 2. User Queue: high-priority explicit user queue (never shuffled, FIFO priority)
  final List<TrackEntity> userQueue = [];

  // 3. Playback History: tracks played prior to current track
  final List<TrackEntity> playbackHistory = [];

  // 4. Actually Played in Session (BloomeeTunes model)
  final List<TrackEntity> actuallyPlayedInSession = [];

  // Active track state
  TrackEntity? currentTrack;
  bool currentTrackIsFromUserQueue = false;

  QueueStateManager({SmartShufflePermutator? shufflePermutator})
      : shufflePermutator = shufflePermutator ?? SmartShufflePermutator();

  /// Next track according to two-tier rules:
  /// 1. User queue has absolute immediate priority
  /// 2. Remaining context tracks
  /// 3. RepeatMode.all loop back to context start
  TrackEntity? getNextTrack(LoopMode loopMode) {
    if (userQueue.isNotEmpty) {
      return userQueue.first;
    }
    final remaining = remainingContextTracks;
    if (remaining.isNotEmpty) {
      return remaining.first;
    }
    if (loopMode == LoopMode.all && contextQueue.isNotEmpty) {
      if (isShuffleEnabled && contextShuffleIndices.isNotEmpty) {
        return contextQueue[contextShuffleIndices[0]];
      }
      return contextQueue[0];
    }
    return null;
  }

  /// Remaining context tracks following current position in context sequence
  List<TrackEntity> get remainingContextTracks {
    if (contextQueue.isEmpty) return const [];
    if (isShuffleEnabled) {
      if (contextIndex + 1 < contextShuffleIndices.length) {
        return contextShuffleIndices
            .sublist(contextIndex + 1)
            .map((i) => contextQueue[i])
            .toList();
      }
      return const [];
    } else {
      if (contextIndex + 1 < contextQueue.length) {
        return contextQueue.sublist(contextIndex + 1);
      }
      return const [];
    }
  }

  /// Merged effective queue: [Played Context] + [Current Track] + [userQueue] + [Remaining contextQueue]
  List<TrackEntity> buildMergedQueue() {
    final result = <TrackEntity>[];
    if (contextQueue.isEmpty && userQueue.isEmpty && currentTrack == null) {
      return result;
    }

    final contextSeq = isShuffleEnabled
        ? contextShuffleIndices.map((i) => contextQueue[i]).toList()
        : contextQueue;

    if (!currentTrackIsFromUserQueue) {
      if (contextIndex > 0 && contextIndex <= contextSeq.length) {
        result.addAll(contextSeq.sublist(0, contextIndex));
      }
      if (currentTrack != null) {
        result.add(currentTrack!);
      }
      result.addAll(userQueue);
      if (contextIndex + 1 < contextSeq.length) {
        result.addAll(contextSeq.sublist(contextIndex + 1));
      }
    } else {
      if (contextIndex >= 0 && contextIndex < contextSeq.length) {
        result.addAll(contextSeq.sublist(0, contextIndex + 1));
      }
      if (currentTrack != null) {
        result.add(currentTrack!);
      }
      result.addAll(userQueue);
      if (contextIndex + 1 < contextSeq.length) {
        result.addAll(contextSeq.sublist(contextIndex + 1));
      }
    }

    return result;
  }

  /// Appends track to user queue with explicit user priority
  void addToUserQueue(TrackEntity entity) {
    userQueue.add(entity.copyWith(isUserEnqueued: true));
  }

  /// Inserts track at specific index in merged queue maintaining two-tier separation
  void insertAt(int index, TrackEntity entity, int curIdx) {
    if (entity.isUserEnqueued) {
      final userOffset = (index - (curIdx + 1)).clamp(0, userQueue.length);
      userQueue.insert(userOffset, entity);
    } else {
      final safeIdx = index.clamp(0, contextQueue.length);
      contextQueue.insert(safeIdx, entity);
      if (isShuffleEnabled) {
        contextShuffleIndices.insert(
          safeIdx.clamp(0, contextShuffleIndices.length),
          contextQueue.length - 1,
        );
      }
      if (safeIdx <= contextIndex) {
        contextIndex++;
      }
    }
  }

  /// Removes track at merged index. Returns true if removing the active current track.
  bool removeAt(int index) {
    final merged = buildMergedQueue();
    if (index < 0 || index >= merged.length) return false;

    final target = merged[index];
    final isRemovingCurrent = currentTrack != null && target.id == currentTrack!.id;

    if (target.isUserEnqueued) {
      userQueue.removeWhere((t) => t.id == target.id);
    } else {
      final ctxIdx = contextQueue.indexWhere((t) => t.id == target.id);
      if (ctxIdx != -1) {
        contextQueue.removeAt(ctxIdx);
        if (isShuffleEnabled) {
          final posInShuffle = contextShuffleIndices.indexOf(ctxIdx);
          if (posInShuffle != -1) contextShuffleIndices.removeAt(posInShuffle);
          for (int i = 0; i < contextShuffleIndices.length; i++) {
            if (contextShuffleIndices[i] > ctxIdx) {
              contextShuffleIndices[i]--;
            }
          }
        }
        if (ctxIdx < contextIndex) {
          contextIndex--;
        }
      }
    }

    return isRemovingCurrent;
  }

  /// Reorders track from oldIndex to newIndex in merged queue
  void reorder(int oldIndex, int newIndex, int curIdx) {
    final merged = buildMergedQueue();
    if (oldIndex < 0 || oldIndex >= merged.length) return;
    if (newIndex < 0 || newIndex > merged.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex) return;

    final movingItem = merged[oldIndex];

    if (movingItem.isUserEnqueued) {
      final oldUserIdx = (oldIndex - (curIdx + 1)).clamp(0, userQueue.length - 1);
      final newUserIdx = (newIndex - (curIdx + 1)).clamp(0, userQueue.length);
      if (oldUserIdx >= 0 && oldUserIdx < userQueue.length) {
        final removed = userQueue.removeAt(oldUserIdx);
        userQueue.insert(newUserIdx.clamp(0, userQueue.length), removed);
      }
    } else {
      final baseOffset = curIdx + 1 + userQueue.length;
      if (isShuffleEnabled && contextShuffleIndices.isNotEmpty) {
        final oldCtxIdx = contextQueue.indexWhere((t) => t.id == movingItem.id);
        final oldShufflePos = contextShuffleIndices.indexOf(oldCtxIdx);
        if (oldShufflePos != -1) {
          final targetShufflePos = (newIndex - userQueue.length).clamp(0, contextShuffleIndices.length - 1);
          final removed = contextShuffleIndices.removeAt(oldShufflePos);
          contextShuffleIndices.insert(targetShufflePos, removed);
        }
      } else {
        final oldCtxIdx = contextQueue.indexWhere((t) => t.id == movingItem.id);
        if (oldCtxIdx != -1) {
          final removed = contextQueue.removeAt(oldCtxIdx);
          final targetCtxOffset = (newIndex >= baseOffset)
              ? (newIndex - userQueue.length)
              : newIndex;
          final safeNewCtxIdx = targetCtxOffset.clamp(0, contextQueue.length);
          contextQueue.insert(safeNewCtxIdx, removed);

          if (oldCtxIdx == contextIndex) {
            contextIndex = safeNewCtxIdx;
          } else if (oldCtxIdx < contextIndex && safeNewCtxIdx >= contextIndex) {
            contextIndex--;
          } else if (oldCtxIdx > contextIndex && safeNewCtxIdx <= contextIndex) {
            contextIndex++;
          }
        }
      }
    }
  }

  /// Clears user queue only
  void clearUserQueue() {
    userQueue.clear();
  }

  /// Clears all queue state
  void clear() {
    contextQueue.clear();
    contextShuffleIndices.clear();
    isShuffleEnabled = false;
    userQueue.clear();
    playbackHistory.clear();
    actuallyPlayedInSession.clear();
    currentTrack = null;
    currentTrackIsFromUserQueue = false;
    contextIndex = -1;
  }
}

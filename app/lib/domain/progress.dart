/// Progress models emitted by the conversion controller and rendered by the UI.
library;

/// Top-level phase of a conversion run, driving the overall UI state.
enum ConvPhase { idle, parsing, synthesizing, assembling, done, error }

/// Status of a single chapter within a run.
enum ChapterStatus {
  /// Not started yet.
  pending,

  /// Synthesizing audio for this chapter's chunks.
  synthesizing,

  /// Merging chunk WAVs into the chapter WAV.
  assembling,

  /// Finished successfully.
  done,

  /// Failed; see [ChapterProgress.error].
  error,

  /// Deliberately excluded by the user.
  skipped,
}

/// Progress for one chapter: how much of its text has been narrated and where
/// it is in the pipeline.
class ChapterProgress {
  /// Chapter index (matches `Chapter.index`).
  final int index;

  /// Chapter title, for display.
  final String title;

  /// Total characters to narrate in this chapter.
  final int totalChars;

  /// Characters narrated so far.
  final int doneChars;

  /// Where this chapter is in the pipeline.
  final ChapterStatus status;

  /// Error message when [status] is [ChapterStatus.error].
  final String? error;

  const ChapterProgress({
    required this.index,
    required this.title,
    required this.totalChars,
    this.doneChars = 0,
    this.status = ChapterStatus.pending,
    this.error,
  });

  /// Completion fraction in `[0, 1]`. A zero-length chapter counts as done so
  /// it never stalls the global bar.
  double get fraction =>
      totalChars == 0 ? 1.0 : (doneChars / totalChars).clamp(0.0, 1.0);

  /// Returns a copy with the provided fields replaced.
  ChapterProgress copyWith({
    int? doneChars,
    ChapterStatus? status,
    String? error,
  }) {
    return ChapterProgress(
      index: index,
      title: title,
      totalChars: totalChars,
      doneChars: doneChars ?? this.doneChars,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}

/// Aggregate progress snapshot for the whole run.
class ConversionProgress {
  /// Current top-level phase.
  final ConvPhase phase;

  /// Per-chapter progress for every selected chapter.
  final List<ChapterProgress> chapters;

  /// Optional human-readable status line for the UI / log header.
  final String? message;

  const ConversionProgress({
    this.phase = ConvPhase.idle,
    this.chapters = const [],
    this.message,
  });

  /// Character-weighted global completion in `[0, 1]`: the sum of narrated
  /// characters over the sum of total characters across all chapters. Returns
  /// 0 when there is no work yet, so the bar starts empty rather than full.
  double get globalFraction {
    final total = chapters.fold<int>(0, (s, c) => s + c.totalChars);
    if (total == 0) return 0.0;
    final done = chapters.fold<int>(0, (s, c) => s + c.doneChars);
    return (done / total).clamp(0.0, 1.0);
  }

  /// Returns a copy with the provided fields replaced.
  ConversionProgress copyWith({
    ConvPhase? phase,
    List<ChapterProgress>? chapters,
    String? message,
  }) {
    return ConversionProgress(
      phase: phase ?? this.phase,
      chapters: chapters ?? this.chapters,
      message: message ?? this.message,
    );
  }
}

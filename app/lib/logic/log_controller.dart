/// Central log sink: collects lines, streams them to the UI, and can persist.
library;

import 'dart:async';
import 'dart:io';

/// Severity of a [LogLine].
enum LogLevel { info, warn, error }

/// One log entry.
class LogLine {
  /// Severity.
  final LogLevel level;

  /// Message text.
  final String message;

  /// When it was recorded.
  final DateTime time;

  LogLine(this.level, this.message, this.time);

  /// `HH:MM:SS LEVEL message` rendering used by [LogController.dump].
  String format() {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s ${level.name.toUpperCase().padRight(5)} $message';
  }
}

/// Buffers log lines (capped ring), broadcasts them to listeners, and supports
/// dumping/saving the full log. Deliberately free of Flutter dependencies so
/// it can be unit-tested directly; Riverpod exposes it to the UI.
class LogController {
  final int _maxLines;
  final List<LogLine> _buffer = [];
  final StreamController<LogLine> _controller =
      StreamController<LogLine>.broadcast();

  /// Creates a controller retaining at most [maxLines] entries (default 5000).
  LogController({int maxLines = 5000}) : _maxLines = maxLines;

  /// Broadcast stream of new lines as they arrive.
  Stream<LogLine> get lines => _controller.stream;

  /// Immutable snapshot of the retained lines.
  List<LogLine> get history => List.unmodifiable(_buffer);

  /// Records an informational line.
  void info(String message) => _add(LogLevel.info, message);

  /// Records a warning line.
  void warn(String message) => _add(LogLevel.warn, message);

  /// Records an error line.
  void error(String message) => _add(LogLevel.error, message);

  void _add(LogLevel level, String message) {
    final line = LogLine(level, message, DateTime.now());
    _buffer.add(line);
    if (_buffer.length > _maxLines) {
      _buffer.removeRange(0, _buffer.length - _maxLines);
    }
    if (!_controller.isClosed) _controller.add(line);
  }

  /// Returns the full retained log as newline-joined formatted text.
  String dump() => _buffer.map((l) => l.format()).join('\n');

  /// Writes [dump] to [path].
  Future<void> saveTo(String path) async {
    await File(path).writeAsString(dump());
  }

  /// Releases the broadcast stream.
  void dispose() => _controller.close();
}

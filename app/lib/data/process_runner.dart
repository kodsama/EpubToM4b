/// The single seam through which the app runs external binaries.
///
/// Every invocation of `ffmpeg`, `piper`, `espeak-ng`, `brew`, etc. goes
/// through a [ProcessRunner]. Production uses [SystemProcessRunner]; tests
/// inject a fake so no real process is spawned.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The captured result of a finished process.
class ProcessRunResult {
  /// Process exit code (0 = success).
  final int exitCode;

  /// Full standard output, decoded as UTF-8.
  final String stdout;

  /// Full standard error, decoded as UTF-8.
  final String stderr;

  const ProcessRunResult(this.exitCode, this.stdout, this.stderr);

  /// Whether the process exited successfully.
  bool get ok => exitCode == 0;
}

/// Thrown when a process exits non-zero and the caller asked for a check.
class ProcessFailure implements Exception {
  /// The executable that failed.
  final String executable;

  /// The result, including the stderr tail.
  final ProcessRunResult result;

  ProcessFailure(this.executable, this.result);

  @override
  String toString() =>
      'ProcessFailure($executable exited ${result.exitCode}): '
      '${_tail(result.stderr)}';

  static String _tail(String s) =>
      s.length <= 2000 ? s : s.substring(s.length - 2000);
}

/// Abstraction over running a child process.
abstract class ProcessRunner {
  /// Runs [executable] with [args], optionally piping [stdinText] to its
  /// standard input, and returns the captured result once it exits.
  Future<ProcessRunResult> run(
    String executable,
    List<String> args, {
    String? stdinText,
  });

  /// Runs [executable] with [args] and streams merged stdout+stderr lines as
  /// they are produced (used for long-running installs).
  Stream<String> stream(
    String executable,
    List<String> args, {
    String? stdinText,
  });

  /// Convenience wrapper that throws [ProcessFailure] on a non-zero exit.
  Future<ProcessRunResult> checked(
    String executable,
    List<String> args, {
    String? stdinText,
  }) async {
    final r = await run(executable, args, stdinText: stdinText);
    if (!r.ok) throw ProcessFailure(executable, r);
    return r;
  }
}

/// Real implementation backed by `dart:io` [Process].
class SystemProcessRunner extends ProcessRunner {
  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> args, {
    String? stdinText,
  }) async {
    final process = await Process.start(executable, args);
    if (stdinText != null) {
      process.stdin.add(utf8.encode(stdinText));
      await process.stdin.flush();
    }
    await process.stdin.close();
    final out = await process.stdout.transform(utf8.decoder).join();
    final err = await process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    return ProcessRunResult(code, out, err);
  }

  @override
  Stream<String> stream(
    String executable,
    List<String> args, {
    String? stdinText,
  }) async* {
    final process = await Process.start(
      executable,
      args,
      mode: ProcessStartMode.normal,
    );
    if (stdinText != null) {
      process.stdin.add(utf8.encode(stdinText));
      await process.stdin.flush();
    }
    await process.stdin.close();

    final controller = StreamController<String>();
    var open = 2;
    void onDone() {
      if (--open == 0) controller.close();
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(controller.add, onDone: onDone);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(controller.add, onDone: onDone);

    yield* controller.stream;
    await process.exitCode;
  }
}

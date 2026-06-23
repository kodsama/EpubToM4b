import 'dart:io';

import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/logic/log_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogController', () {
    test('buffers lines and exposes them via history and dump', () {
      final log = LogController();
      log.info('starting');
      log.warn('careful');
      log.error('boom');
      expect(log.history.length, 3);
      expect(log.history.map((l) => l.level),
          [LogLevel.info, LogLevel.warn, LogLevel.error]);
      expect(log.dump(), contains('INFO  starting'));
      expect(log.dump(), contains('ERROR boom'));
      log.dispose();
    });

    test('emits new lines on the broadcast stream', () async {
      final log = LogController();
      final received = <String>[];
      final sub = log.lines.listen((l) => received.add(l.message));
      log.info('one');
      log.info('two');
      await Future<void>.delayed(Duration.zero);
      expect(received, ['one', 'two']);
      await sub.cancel();
      log.dispose();
    });

    test('caps the ring buffer at maxLines', () {
      final log = LogController(maxLines: 3);
      for (var i = 0; i < 10; i++) {
        log.info('line $i');
      }
      expect(log.history.length, 3);
      expect(log.history.first.message, 'line 7');
      expect(log.history.last.message, 'line 9');
      log.dispose();
    });
  });

  group('SystemProcessRunner', () {
    // POSIX-only: `echo` semantics differ on Windows shells.
    test('captures stdout and exit code', () async {
      final r = await SystemProcessRunner().run('echo', ['hello']);
      expect(r.exitCode, 0);
      expect(r.stdout.trim(), 'hello');
      expect(r.ok, isTrue);
    }, skip: Platform.isWindows);

    test('checked() throws ProcessFailure on non-zero exit', () async {
      // `false` always exits 1 on POSIX systems.
      expect(
        () => SystemProcessRunner().checked('false', const []),
        throwsA(isA<ProcessFailure>()),
      );
    }, skip: Platform.isWindows);

    test('pipes stdin to the process', () async {
      final r = await SystemProcessRunner().run('cat', const [], stdinText: 'piped');
      expect(r.stdout, 'piped');
    }, skip: Platform.isWindows);
  });
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

/// Lightweight rolling file logger for diagnosing crashes, playback lifecycle,
/// and foreground service state on client devices.
class AppLogger {
  static const String _logFileName = 'paatu_app_log.txt';
  static const int _maxFileSizeBytes = 512 * 1024; // 512 KB cap

  static File? _logFile;
  static final _queue = StreamController<String>();
  static bool _initialized = false;
  static final List<String> _preInitBuffer = [];

  /// Initialize file sink and background sequential processor
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_logFileName');
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
      _initialized = true;

      // Drain queue sequentially via asyncMap to guarantee strict FIFO ordering without concurrent write races
      _queue.stream.asyncMap((message) async {
        await _writeToFile(message);
      }).listen((_) {});

      // Flush messages logged prior to initialization
      for (final buffered in _preInitBuffer) {
        _queue.add(buffered);
      }
      _preInitBuffer.clear();

      log('AppLogger', 'Logger initialized successfully. Platform: ${Platform.operatingSystem}');
    } catch (e) {
      debugPrint('[AppLogger] Initialization error: $e');
    }
  }

  /// Logs a structured message with ISO-8601 timestamp, log level, and component tag
  static void log(String tag, String message, {LogLevel level = LogLevel.info}) {
    final timestamp = DateTime.now().toIso8601String();
    final levelStr = level.name.toUpperCase();
    final entry = '[$timestamp] [$levelStr] [$tag] $message\n';
    debugPrint(entry.trim());

    if (_initialized) {
      _queue.add(entry);
    } else if (_preInitBuffer.length < 500) {
      _preInitBuffer.add(entry);
    }
  }

  static void debug(String tag, String message) => log(tag, message, level: LogLevel.debug);
  static void info(String tag, String message) => log(tag, message, level: LogLevel.info);
  static void warn(String tag, String message) => log(tag, message, level: LogLevel.warn);

  /// Records an uncaught exception or fatal error with full stack trace
  static void recordError(dynamic error, StackTrace? stackTrace, {String? context}) {
    final ctx = context != null ? ' ($context)' : '';
    final entry = 'ERROR$ctx: $error\n${stackTrace ?? StackTrace.current}\n';
    log('CRASH/FATAL', entry, level: LogLevel.error);
  }

  /// Appends message to disk and rolls log if file exceeds size cap
  static Future<void> _writeToFile(String text) async {
    try {
      if (_logFile == null) return;
      if (await _logFile!.exists()) {
        final length = await _logFile!.length();
        if (length > _maxFileSizeBytes) {
          // Truncate oldest half of the file
          final content = await _logFile!.readAsString();
          final lines = content.split('\n');
          final halfLines = lines.sublist((lines.length / 2).floor());
          await _logFile!.writeAsString('--- LOG ROLLED ---\n${halfLines.join('\n')}\n', mode: FileMode.write, flush: true);
        }
      }
      await _logFile!.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[AppLogger] Write failure: $e');
    }
  }

  /// Retrieves entire log content as a string for in-app viewing or export
  static Future<String> getLogContent() async {
    try {
      if (_logFile == null) {
        final dir = await getApplicationDocumentsDirectory();
        _logFile = File('${dir.path}/$_logFileName');
      }
      if (await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
    } catch (e) {
      return 'Failed to read logs: $e';
    }
    return 'No log entries recorded yet.';
  }

  /// Clears the log file
  static Future<void> clearLog() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('--- LOG CLEARED AT ${DateTime.now().toIso8601String()} ---\n');
      }
    } catch (e) {
      debugPrint('[AppLogger] Clear log error: $e');
    }
  }

  /// Gets the absolute path of the log file for sharing
  static String? get logFilePath => _logFile?.path;
}

import 'package:srt_dart/src/open.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:srt_dart/srt_dart.dart';

/// Global SRT instance for lifecycle management

class Srt {
  static late srt_dart_bindings _bindings;
  static bool _initialized = false;
  static final Map<int, SrtSocket> _sockets = {};

  static set addSocket(SrtSocket socket) {
    _sockets[socket.socketHandle] = socket;
  }

  static set removeSocket(SrtSocket socket) {
    _sockets.remove(socket.socketHandle);
  }

  /// Get the bindings instance, initializing if necessary
  static srt_dart_bindings get bindings {
    if (!_initialized) {
      _bindings = srt_dart_bindings(dylib);
      _initialized = true;
    }
    return _bindings;
  }

  static SrtSocket getSocket(int handle){
    return _sockets[handle]!;
  }

  /// Initialize the SRT library
  ///
  /// This must be called once before creating any SRT sockets.
  /// Typically called in main() or early in application startup.
  ///
  /// Throws [SrtException] if initialization fails
  ///
  Srt() {
    final result = bindings.srt_startup();
    checkSrtResult(result, operation: 'srt_startup');
  }

  /// Clean up the SRT library and release all resources
  ///
  /// Should be called before application shutdown.
  /// After calling this, no SRT operations are permitted.
  static void cleanUp() {
    for (final socket in _sockets.values) {
      socket.dispose();
    }

    _sockets.clear();

    if (_initialized) {
      bindings.srt_cleanup();
      _initialized = false;
    }
  }
}

import 'package:srt_dart/src/open.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:srt_dart/src/exceptions.dart';

/// Global SRT instance for lifecycle management

class Srt{
  static late srt_dart_bindings _bindings;
  static bool _initialized = false;

  /// Get the bindings instance, initializing if necessary
  static srt_dart_bindings get bindings {
    if (!_initialized) {
      _bindings = srt_dart_bindings(dylib);
      _initialized = true;
    }
    return _bindings;
  }

  /// Initialize the SRT library
  /// 
  /// This must be called once before creating any SRT sockets.
  /// Typically called in main() or early in application startup.
  /// 
  /// Throws [SrtException] if initialization fails
  Srt() {
    final result = bindings.srt_startup();
    checkSrtResult(result, operation: 'srt_startup');
  }

  /// Clean up the SRT library and release all resources
  /// 
  /// Should be called before application shutdown.
  /// After calling this, no SRT operations are permitted.
  void cleanUp() {
    bindings.srt_cleanup();
  }

}


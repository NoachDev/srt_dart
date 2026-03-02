import 'package:ffi/ffi.dart';
import 'package:srt_dart/main.dart';
import 'package:srt_dart/src/srt_socket.dart';
import 'package:srt_dart/srt_dart.dart';

/// Exception raised when an SRT operation fails.
///
/// This exception wraps SRT API errors with human-readable error messages.
class SrtException implements Exception {
  /// The error message from SRT.
  final String message;

  /// The SRT error code (optional).
  final int? errorCode;

  /// Creates an [SrtException] with the given message and optional error code.
  SrtException(this.message, {this.errorCode});

  /// Creates an [SrtException] from the last SRT error.
  ///
  /// This factory constructor retrieves the error message from the SRT library's
  /// error buffer using [srt_getlasterror_str].
  factory SrtException.fromLastError() {
    final errorPtr = Srt.bindings.srt_getlasterror_str();
    final message = errorPtr.cast<Utf8>().toDartString();
    return SrtException(message);
  }

  @override
  String toString() =>
      'SrtException: $message${errorCode != null ? ' (code: $errorCode)' : ''}';
}

/// Helper to check SRT function return values.
///
/// SRT functions typically return -1 on error. This function wraps the check
/// and throws an [SrtException] if an error occurred.
void checkSrtResult(int result, {required String operation , nonexpected = -1 , int? handle }) {
  if (result == nonexpected) {
    print('Error during $operation');

    if(handle != null){
      final socket = SrtSocket.fromHandle(handle);
      print("Socket data :");
      print("\t status : ${socket.status}");
      if (!operation.contains("name") && socket.status == SRT_SOCKSTATUS.SRTS_CONNECTED){
        print("\t peer : ${socket.getRemoteAddress()}");
      }
    }
    
    throw SrtException.fromLastError();
  }
}

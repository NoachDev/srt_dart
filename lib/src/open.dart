import 'dart:ffi';
import 'dart:io';

final DynamicLibrary dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    // unsupporte for now
    throw UnsupportedError('MacOS and iOS are unsupported at this time.');
    // return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open(
      '/mnt/extencion/Projects/srt_dart/lib/src/bindings/libsrt.so',
    );
  }
  if (Platform.isWindows) {
    // unsupporte for now
    throw UnsupportedError('Windows are unsupported at this time.');
    // return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

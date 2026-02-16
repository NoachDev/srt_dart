import 'dart:ffi';

import 'package:path/path.dart' as path;

DynamicLibrary get dylib {
  try{
    return _initlizePath(Abi.current().libName);
  }
  catch(e){
    final libPath = path.join(Abi.current().pathName, Abi.current().libName);
    return _initlizePath(libPath);
  }
}

DynamicLibrary _initlizePath(String libraryPath){
  return DynamicLibrary.open(libraryPath);
}

extension on Abi{
  String get libName {
    switch (Abi.current()) {
      case Abi.linuxX64:
        return 'libsrt.so';
      default:
        throw UnsupportedError(
          'Unsupported processor architecture "${Abi.current()}". '
          'Please open an issue on GitHub to request it.',
        );
    }
  }

  String get pathName{
    switch (Abi.current()) {
      case Abi.linuxX64:
        return '/usr/local/lib';
      default:
        throw UnsupportedError(
          'Unsupported loacal path architecture "${Abi.current()}". '
          'Please open an issue on GitHub to request it.',
        );
    }
    
  }
}

import 'package:srt_dart/src/open.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:srt_dart/src/options.dart';

class SrtSocket {
  final srt_dart_bindings _bindings;
  late Options options;
  late int fhandle;

  SrtSocket(Options? opt) : _bindings = srt_dart_bindings(dylib){
    options = opt ?? Options();

    _bindings.srt_startup();
    fhandle = _bindings.srt_create_socket();
  }
  
  void dispose(){
    _bindings.close(fhandle);
    _bindings.srt_cleanup();
  }
}
import 'dart:isolate';

/// [bool] identify if is unique or can have mutlipys
class IsolateData {
  final receivePort = ReceivePort();
  late Isolate isolate;

  IsolateData();
}

class IsolateInfo {
  final String? menssage;
  final bool unique;
  final int? timeOut;

  final Function action;

  IsolateInfo({
    required this.unique,
    required this.action,
    this.menssage,
    this.timeOut,
  });
}

/// Manger of Isolates for async operations
///
/// [masks] conatein the allowed actions and your names.
/// [_threads] is a map of process runing
///
abstract class ThreadMananger {
  final Map<String, IsolateInfo> masks = {};
  final Map<String, Map<int, IsolateData>> _threads = {};
  int _PID_POINTER = 0;

  void removeData(String name, int pid) {
    final data = _threads[name]![pid]!;

    data.isolate.kill(priority: Isolate.immediate);
    data.receivePort.close();
    _threads[name]!.remove(pid);
  }

  void clean() {
    for (final mask in _threads.keys) {
      for (final pid in _threads[mask]!.keys) {
        removeData(mask, pid);
      }
    }
  }

  Future<IsolateData> runInIsolate(String name, {dynamic arg}) async {
    if (!masks.containsKey(name)) {
      throw ArgumentError("Invalid thread mask name $name");
    }

    final threadInfo = masks[name]!;

    if (_threads.containsKey(name)) {
      if (threadInfo.unique && _threads[name]!.isNotEmpty) {
        throw Exception(threadInfo.menssage);
      }
    } else {
      _threads[name] = {};
    }

    final data = IsolateData();

    data.isolate = await Isolate.spawn(
      (sendPort) async {
        late dynamic result;

        if (arg != null) {
          result = threadInfo.action(arg);
        } else {
          result = threadInfo.action();
        }

        sendPort.send(result);
      },
      data.receivePort.sendPort,
      onError: data.receivePort.sendPort,
      debugName: "Isolate from $name PID ${_threads[name]!.length}",
      errorsAreFatal: true,
    );

    _threads[name]![_PID_POINTER++] = (data);

    return data;
  }

  Future<dynamic> getFisrt(String name, {dynamic arg}) async {
    final oldPID = _PID_POINTER;
    try{
      final IsolateData data = await runInIsolate(name, arg: arg);
      final elem = data.receivePort.first;

      // if (threadInfo.timeOut != null) {
      // final threadInfo = masks[name]!;
      /// TODO: Resolve the errors with the C.
      //   return await elem.timeout(Duration(milliseconds: threadInfo.timeOut!));
      // }

      final result = await elem;

      if (result is List) {
        if (result.isNotEmpty &&
            result[0] is String &&
            result[0].contains("SrtException")) {
          throw result[0];
        }
      }

      return result;
    }
    finally{
      removeData(name, oldPID);
    }
  }
}

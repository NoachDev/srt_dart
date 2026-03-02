import 'dart:isolate';

/// [bool] identify if is unique or can have mutlipys
class IsolateData {
  final receivePort = ReceivePort();
  late Isolate isolate;

  IsolateData();
}

class IsolateInfo{
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
  final Map<String, List<IsolateData>> _threads = {};

  void dispose() {
    for (final threads in _threads.values) {
      for (final thread in threads) {
        thread.receivePort.close();
      }
    }
    _threads.clear();
  }

  Future<dynamic> runInIsolate(String name, { dynamic arg }) async {
    if (!masks.containsKey(name)) {
      throw ArgumentError("Invalid thread mask name $name");
    }

    final threadInfo = masks[name]!;

    if (_threads.containsKey(name)) {
      if (threadInfo.unique && _threads[name]!.isNotEmpty) {
        throw Exception(threadInfo.menssage);
      }
    } else {
      _threads[name] = [];
    }

    final data = IsolateData();

    data.isolate = await Isolate.spawn(
      (sendPort) {
        late dynamic result;
        if (arg != null) {
          result = threadInfo.action(arg);
        }else{
          result = threadInfo.action();
        }
        sendPort.send(result);
      },
      data.receivePort.sendPort,
      debugName: "Isolate from $name PID ${_threads[name]!.length}",
      errorsAreFatal: true,
    );

    _threads[name]!.add(data);

    try {
      final elem = data.receivePort.first;

      if (threadInfo.timeOut != null) {
        /// TODO: Resolve the errors with the C.
        return await elem.timeout(Duration(milliseconds: threadInfo.timeOut!));
      }

      return await elem;
    }
    finally {
      data.isolate.kill(priority: Isolate.immediate);
      data.receivePort.close();
      _threads[name]!.remove(data);
    }

  }
}

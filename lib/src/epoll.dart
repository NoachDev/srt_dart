import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:srt_dart/src/async.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:srt_dart/src/srt_socket.dart';
import 'package:srt_dart/src/exceptions.dart';
import 'package:srt_dart/main.dart';

/// Represents SRT event types that can occur on a socket
enum EpollEventType {
  /// Socket is ready to accept.
  accept,

  /// Socket is a connected socket.
  connected,

  /// An socket ready to accept and connected.
  both,

  /// A Dart handle to notify when a udp package is icoming
  read,
}

/// Represents a single epoll event from waitAsync()
class EpollEvent {
  /// The socket handle that generated this event
  final SrtSocket socket;

  /// The type of event that occurred
  final EpollEventType type;

  EpollEvent({required this.socket, required this.type});

  @override
  String toString() => 'EpollEvent(socket=$socket, type=$type)';
}

/// Manages event-driven multiplexing for multiple SRT sockets
///
/// SrtEpoll enables scalable, non-blocking I/O patterns by monitoring
/// multiple sockets simultaneously. Instead of blocking on individual
/// sockets or using isolates per socket, epoll allows a single thread
/// to handle many concurrent connections efficiently.
///
/// Basic usage:
/// ```dart
/// final epoll = SrtEpoll();
///
/// // Add sockets to monitor
/// final socket1 = SrtSocket();
/// socket1.bind('0.0.0.0', 4200);
/// socket1.listen();
/// epoll.register(socket1, events: [EpollEventType.read]);
///
/// // Wait for events
/// await for (final event in epoll.waitAsync(timeout: 1000)) {
///   if (event.type == EpollEventType.read) {
///     final data = event.socket.recvStream();
///     print('Received: $data');
///   }
/// }
///
/// // Cleanup
/// epoll.dispose();
/// ```
class SrtEpoll {
  /// The underlying epoll file descriptor from SRT
  final int _epollHandle;

  /// Whether this epoll has been closed
  bool _isClosed = false;

  /// A register of Sockets events, if true has a read Event
  final Map<int, bool> _registeredEvents = {};

  int _timeoutMs = 100;
  int _maxEvents = 100;

  late EpollThread _asyncControl;

  /// [timeOutMs] Set the timout for waiting events on Epoll
  /// [maxEvents] Is the maximum number of accept/connect/both events of waitAsync/
  set timeOutMs(int value) => _timeoutMs = max(0, value);
  set maxEvents(int value) => _maxEvents = max(1, value);

  /// Create a new SRT epoll instance
  ///
  /// Throws [SrtException] if epoll creation fails
  SrtEpoll() : _epollHandle = Srt.bindings.srt_epoll_create() {
    checkSrtResult(_epollHandle, operation: 'create epoll instance');
    _asyncControl = EpollThread(this);
  }

  /// Register a socket for event monitoring
  ///
  /// [socket] is the SRT socket to monitor
  /// [events] specifies which event types to monitor (default: all)
  ///
  /// Multiple calls with the same socket will update the monitored events.
  ///
  /// Throws [SrtException] if registration fails
  void register(
    SrtSocket socket, {
    List<EpollEventType> events = const [
      EpollEventType.accept,
      EpollEventType.connected,
    ],
  }) {
    _checkNotClosed();

    // Convert event types to SRT_EPOLL_OPT bitmask
    int eventMask = 0;

    if (events.contains(EpollEventType.read)) {
      /// remove the read event, is only for Dart
      events.remove(EpollEventType.read);
    }

    /// if is read only, no need register in srt_epoll
    if (events.isEmpty) {
      _registeredEvents[socket.socketHandle] = true;
      return;
    }

    for (final event in events) {
      eventMask |= _eventTypeToBitmask(event);
    }

    final eventPtr = calloc<ffi.Int>();

    try {
      eventPtr.value = eventMask;

      final result = Srt.bindings.srt_epoll_add_usock(
        _epollHandle,
        socket.socketHandle,
        eventPtr,
      );

      checkSrtResult(result, operation: "registering the socket ${socket.socketHandle} in epoll");

      // Track registered socket for event delivery
    } finally {
      calloc.free(eventPtr);
    }
  }

  /// Unregister a socket from event monitoring
  ///
  /// [socket] is the SRT socket to stop monitoring
  ///
  /// Throws [SrtException] if unregistration fails
  /// 
  void unregister(SrtSocket socket) {
    _checkNotClosed();

    final result = Srt.bindings.srt_epoll_remove_usock(_epollHandle, socket.socketHandle);
    checkSrtResult(result, operation: "unregistering the socket ${socket.socketHandle} in epoll");

    _registeredEvents.remove(socket.socketHandle);
  }

  /// Wait asynchronously for events on registered sockets
  ///
  /// This is a non-blocking operation that suspends until either:
  /// - An event occurs on a registered socket
  /// - The timeout expires
  /// - An error occurs
  ///
  /// [timeOutIsCritical] is for timeout in read events
  /// [errorsIsCritical] is for timeout in accept/connect/both events
  ///
  /// Returns a Future that completes with a list of [EpollEvent] objects
  /// representing the events that occurred. The list will be empty if
  /// the timeout was reached without any events.
  ///
  /// Example:
  /// ```dart
  /// final epoll = SrtEpoll();
  /// epoll.register(socket1, events: [EpollEventType.read]);
  /// epoll.register(socket2, events: [EpollEventType.write]);
  ///
  /// final events = await epoll.waitAsync();
  /// for (final event in events) {
  ///   print('Event on socket: ${event.type}');
  /// }
  /// ```
  ///
  /// Throws [SrtException] if the epoll_wait operation fails
  /// Throws [TimeoutException] if the read operation fails
  /// 
  Future<List<EpollEvent>> waitAsync({ bool timeOutIsCritical = true, bool errorsIsCritical = true}) async {
    _checkNotClosed();

    final events = <EpollEvent>[];

    final readEvents = _registeredEvents.keys.where(
      (e) => _registeredEvents[e]!,
    );

    for (final socketHandle in readEvents) {
      try {
        await _packageReceived(
          socketHandle,
        ).timeout(Duration(milliseconds: _timeoutMs));

        events.add(
          EpollEvent(
            socket: Srt.getSocket(socketHandle),
            type: EpollEventType.read,
          ),
        );
      } on TimeoutException {
        if (timeOutIsCritical){
          rethrow;
        }
        return events;
      }

      continue;
    }

    /// on only have read Events on SrtEpoll, not is needed use the WaitAsyncMethod
    if (readEvents.length == _registeredEvents.length) {
      return events;
    }

    final Map<String, List<int>> data = await _asyncControl.getFisrt(
      "WaitAsyncMethod",
      arg: errorsIsCritical,
    );

    for (final socketHandle in data["read_socks"]!) {
      events.add(
        EpollEvent(
          socket: Srt.getSocket(socketHandle),
          type: EpollEventType.accept,
        ),
      );
    }
    for (final socketHandle in data["write_socks"]!) {
      events.add(
        EpollEvent(
          socket: Srt.getSocket(socketHandle),
          type: EpollEventType.connected,
        ),
      );
    }

    return events;
  }

  /// Wait asynchronously for events on registered sockets as a Stream
  ///
  /// Creates a continuous stream of [EpollEvent] objects, emitting whenever
  /// events occur on registered sockets. This is useful for reactive,
  /// event-driven architectures.
  ///
  /// Example with await for:
  /// ```dart
  /// await for (final event in epoll.waitAsStream()) {
  ///   switch (event.type) {
  ///     case EpollEventType.read:
  ///       final data = event.socket.recvStream();
  ///       handleData(data);
  ///     case EpollEventType.connect:
  ///       event.socket.sendStream(queuedData);
  ///     _ => return;
  ///   }
  /// }
  /// ```
  ///
  /// The stream continues indefinitely until the epoll is disposed or a timout occour ( if [stopOnTimeout] ).
  /// To stop the stream, call [dispose].
  ///
  /// Throws [SrtException] if wait operations fail
  ///
  Stream<EpollEvent> waitStream({bool stopOnTimeout = true}) async* {
    // Timer.periodic(Duration(milliseconds: ), callback)
    while (!_isClosed) {
      try {
        final events = await waitAsync(timeOutIsCritical: false, errorsIsCritical: stopOnTimeout);
        if (events.isEmpty) {
          if(stopOnTimeout){
            break;
          }
          await Future.delayed(Duration(milliseconds: _timeoutMs));
        }

        for (final event in events) {
          yield event;
        }
      } catch (e) {
        if (_isClosed) {
          break;
        }
        rethrow;
      }
    }
  }

  /// Unregister all sockets and clear the epoll
  ///
  /// After calling this, you can still use register() to add new sockets.
  ///
  /// Throws [SrtException] if clearing fails
  void clear() {
    _checkNotClosed();

    final result = Srt.bindings.srt_epoll_clear_usocks(_epollHandle);
    _asyncControl.clean();

    if (result != 0) {
      throw SrtException.fromLastError();
    }

    _registeredEvents.clear();
  }

  /// Close this epoll and release its resources
  ///
  /// After calling [dispose], this epoll cannot be used anymore.
  /// Calling any other method will throw [StateError].
  ///
  /// Safe to call multiple times (subsequent calls are no-ops)
  void dispose() {
    if (_isClosed) return;
    _asyncControl.clean();

    final result = Srt.bindings.srt_epoll_release(_epollHandle);
    if (result != -1) {
      _isClosed = true;
    }
    _registeredEvents.clear();
  }

  /// Check if epoll is closed, throw if it is
  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('SrtEpoll is closed and cannot be used');
    }
  }

  /// Convert EpollEventType to SRT event bitmask
  int _eventTypeToBitmask(EpollEventType event) {
    return switch (event) {
      EpollEventType.accept => SRT_EPOLL_OPT.SRT_EPOLL_IN.value,
      EpollEventType.connected => SRT_EPOLL_OPT.SRT_EPOLL_OUT.value,
      EpollEventType.both => SRT_EPOLL_OPT.SRT_EPOLL_ERR.value,
      _ => throw ArgumentError('Unsupported event type: $event'),
    };
  }

  Future<bool> _packageReceived(int handle) async {
    final socket = Srt.getSocket(handle);

    while (true) {
      final stats = socket.statistics;

      if (stats.recvPointer < stats.pktRecvTotal) {
        stats.addToPointer();

        break;
      }

      await Future.delayed(Duration(milliseconds: 10));
    }

    return true;
  }

  Map<String, List<int>> _waitAsyncMethod([bool errorsIsCritical = true]) {
    // Allocate arrays for read/write events
    final readFds = calloc<SRTSOCKET>(_maxEvents);
    final readNum = calloc<ffi.Int>();
    final writeFds = calloc<SRTSOCKET>(_maxEvents);
    final writeNum = calloc<ffi.Int>();

    try {
      readNum.value = _maxEvents;
      writeNum.value = _maxEvents;

      // Wait for events
      final result = Srt.bindings.srt_epoll_wait(
        _epollHandle,
        readFds,
        readNum,
        writeFds,
        writeNum,
        _timeoutMs,
        ffi.nullptr.cast<SYSSOCKET>(),
        ffi.nullptr.cast<ffi.Int>(),
        ffi.nullptr.cast<SYSSOCKET>(),
        ffi.nullptr.cast<ffi.Int>(),
      );

      if (!errorsIsCritical && result == -1) {
        return {};
      }

      checkSrtResult(result, operation: 'srt_epoll_wait');

      final readSocks = List.generate(readNum.value, (i) => readFds[i]);
      final writeSocks = List.generate(writeNum.value, (i) => writeFds[i]);

      return {"read_socks": readSocks, "write_socks": writeSocks};
    } finally {
      calloc.free(readFds);
      calloc.free(readNum);
      calloc.free(writeFds);
      calloc.free(writeNum);
    }
  }

}

class EpollThread extends ThreadMananger {
  final SrtEpoll epoll;
  EpollThread(this.epoll) {
    // masks["waitStream"] = IsolateInfo(
    //   unique: true,
    //   menssage: "You aleready wating for events",
    //   action: epoll._waitStreamMethod,
    // );
    masks["WaitAsyncMethod"] = IsolateInfo(
      unique: true,
      menssage: "You aleready wating for events",
      action: epoll._waitAsyncMethod,
    );
  }
}

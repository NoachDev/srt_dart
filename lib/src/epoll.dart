import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:srt_dart/src/srt_socket.dart';
import 'package:srt_dart/src/exceptions.dart';
import 'package:srt_dart/main.dart';

/// Represents SRT event types that can occur on a socket
enum EpollEventType {
  /// Socket is ready to receive data
  read,

  /// Socket is ready to send data
  write,

  /// An error occurred on the socket
  error,
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

  /// Map of socket handles to SrtSocket instances for event delivery
  final Map<int, SrtSocket> _registeredSockets = {};

  /// Create a new SRT epoll instance
  ///
  /// Throws [SrtException] if epoll creation fails
  SrtEpoll() : _epollHandle = Srt.bindings.srt_epoll_create() {
    checkSrtResult(_epollHandle, operation: 'create epoll instance');
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
      EpollEventType.read,
      EpollEventType.write,
      EpollEventType.error,
    ],
  }) {
    _checkNotClosed();

    // Convert event types to SRT_EPOLL_OPT bitmask
    int eventMask = 0;
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

      if (result != 0) {
        throw SrtException.fromLastError();
      }

      // Track registered socket for event delivery
      _registeredSockets[socket.socketHandle] = socket;
    } finally {
      calloc.free(eventPtr);
    }
  }

  /// Unregister a socket from event monitoring
  ///
  /// [socket] is the SRT socket to stop monitoring
  ///
  /// Safe to call multiple times with the same socket.
  ///
  /// Throws [SrtException] if unregistration fails
  void unregister(SrtSocket socket) {
    _checkNotClosed();

    if (_registeredSockets.containsKey(socket.socketHandle)) {
      Srt.bindings.srt_epoll_remove_usock(_epollHandle, socket.socketHandle);
      _registeredSockets.remove(socket.socketHandle);
    }
  }

  /// Wait asynchronously for events on registered sockets
  ///
  /// This is a non-blocking operation that suspends until either:
  /// - An event occurs on a registered socket
  /// - The timeout expires
  /// - An error occurs
  ///
  /// [timeoutMs] is the timeout in milliseconds (0 = immediate return)
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
  /// final events = await epoll.waitAsync(timeoutMs: 1000);
  /// for (final event in events) {
  ///   print('Event on socket: ${event.type}');
  /// }
  /// ```
  ///
  /// Throws [SrtException] if the wait operation fails
  Future<List<EpollEvent>> waitAsync(int timeoutMs, { int maxEvents = 10, errorsIsCritical = true}) async {
    _checkNotClosed();

    // Allocate arrays for read/write events
    final readFds = calloc<SRTSOCKET>(maxEvents);
    final readNum = calloc<ffi.Int>();
    final writeFds = calloc<SRTSOCKET>(maxEvents);
    final writeNum = calloc<ffi.Int>();

    try {
      readNum.value = maxEvents;
      writeNum.value = maxEvents;

      // Wait for events
      final result = Srt.bindings.srt_epoll_wait(
        _epollHandle,
        readFds,
        readNum,
        writeFds,
        writeNum,
        timeoutMs,
        ffi.nullptr.cast<SYSSOCKET>(),
        ffi.nullptr.cast<ffi.Int>(),
        ffi.nullptr.cast<SYSSOCKET>(),
        ffi.nullptr.cast<ffi.Int>(),
      );

      if (!errorsIsCritical && result == -1) {
        return [];
      }

      checkSrtResult(result, operation: 'srt_epoll_wait');

      // Collect events from the results
      final events = <EpollEvent>[];

      // Process read events
      final actualReadNum = readNum.value;

      for (int i = 0; i < actualReadNum; i++) {
        final socketHandle = readFds[i];
        final socket = _registeredSockets[socketHandle];

        if (socket != null) {
          events.add(EpollEvent(socket: socket, type: EpollEventType.read));
        }
      }

      // Process write events
      final actualWriteNum = writeNum.value;

      for (int i = 0; i < actualWriteNum; i++) {
        final socketHandle = writeFds[i];
        final socket = _registeredSockets[socketHandle];

        if (socket != null) {
          events.add(EpollEvent(socket: socket, type: EpollEventType.write));
        }
      }

      return events;
      
    } finally {
      calloc.free(readFds);
      calloc.free(readNum);
      calloc.free(writeFds);
      calloc.free(writeNum);
    }
  }

  /// Wait asynchronously for events on registered sockets as a Stream
  ///
  /// Creates a continuous stream of [EpollEvent] objects, emitting whenever
  /// events occur on registered sockets. This is useful for reactive,
  /// event-driven architectures.
  ///
  /// [timeoutMs] is the timeout for each wait call
  ///
  /// Example with await for:
  /// ```dart
  /// await for (final event in epoll.waitAsStream()) {
  ///   switch (event.type) {
  ///     case EpollEventType.read:
  ///       final data = event.socket.recvStream();
  ///       handleData(data);
  ///     case EpollEventType.write:
  ///       event.socket.sendStream(queuedData);
  ///     case EpollEventType.error:
  ///       handleError(event.socket);
  ///   }
  /// }
  /// ```
  ///
  /// The stream continues indefinitely until the epoll is disposed or a timout error ( if [timeoutIsCritical] ).
  /// To stop the stream, call [dispose].
  ///
  /// Throws [SrtException] if wait operations fail
  /// 
  Stream<EpollEvent> waitAsStream({int timeoutMs = 1000, timeoutIsCritical = true}) async* {
    while (!_isClosed) {
      try {
        final events = await waitAsync(timeoutMs, errorsIsCritical: false);
        for (final event in events) {
          yield event;
        }
        if (events.isEmpty && timeoutIsCritical) {
          break;
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
    if (result != 0) {
      throw SrtException.fromLastError();
    }

    _registeredSockets.clear();
  }

  /// Close this epoll and release its resources
  ///
  /// After calling [dispose], this epoll cannot be used anymore.
  /// Calling any other method will throw [StateError].
  ///
  /// Safe to call multiple times (subsequent calls are no-ops)
  void dispose() {
    if (_isClosed) return;

    final result = Srt.bindings.srt_epoll_release(_epollHandle);
    if (result != -1) {
      _isClosed = true;
    }
    _registeredSockets.clear();
  }

  /// Check if epoll is closed, throw if it is
  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('SrtEpoll is closed and cannot be used');
    }
  }

  /// Convert EpollEventType to SRT event bitmask
  static int _eventTypeToBitmask(EpollEventType event) {
    return switch (event) {
      EpollEventType.read => SRT_EPOLL_OPT.SRT_EPOLL_IN.value,
      EpollEventType.write => SRT_EPOLL_OPT.SRT_EPOLL_OUT.value,
      EpollEventType.error => SRT_EPOLL_OPT.SRT_EPOLL_ERR.value,
    };
  }
}

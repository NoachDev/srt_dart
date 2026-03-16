import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:srt_dart/src/async.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'dart:io';
import 'package:srt_dart/src/options.dart';
import 'package:srt_dart/src/exceptions.dart';
import 'package:srt_dart/src/address.dart';
import 'package:srt_dart/src/message.dart';
import 'package:srt_dart/src/statistics.dart';
import 'package:srt_dart/main.dart';

/// Represents an SRT (Secure Reliable Transport) socket
///
/// An SrtSocket wraps the native SRT C API and provides:
/// - Connection establishment (bind, listen, accept, connect)
/// - Data transmission (send, receive)
/// - Configuration (socket options)
/// - State inspection (status, statistics)
///
/// Basic usage:
/// ```dart
/// // Create and connect as client
/// final socket = SrtSocket();
/// await socket.connect('192.168.1.100', 4200);
/// socket.send(Uint8List.fromList([1, 2, 3]));
/// final data = socket.recv(1024);
///
/// // Or bind and listen as server
/// final serverSocket = SrtSocket();
/// serverSocket.bind('0.0.0.0', 4200);
/// serverSocket.listen();
/// final client = serverSocket.accept();
///
/// // afterwards dispose the socket
/// *.dispose();
///
/// ```
class SrtSocket {
  /// The underlying FFI bindings

  /// The socket file descriptor from SRT
  final int _socketHandle;

  final _statistics = SocketStats();

  late SocketThread _asyncControl;

  /// Whether this socket has been closed
  bool _isClosed = false;

  /// Options of the socket.
  SocketOptions? options;

  /// Get the socket handle
  int get socketHandle => _socketHandle;

  /// Get the current status of this socket
  ///
  /// Returns a [SRT_SOCKSTATUS] enum value indicating the socket state
  ///
  SRT_SOCKSTATUS get status => Srt.bindings.srt_getsockstate(_socketHandle);

  /// Check if this socket is currently closed
  bool get isClosed => _isClosed;

  /// Accept an incoming connection on this socket
  ///
  /// * Must call [listen] before [accept]
  ///
  /// * Ensure the dispose will called or has an incoming connection. Otherwise, the program will crash.
  ///
  /// Returns a new [SrtSocket] representing the connected client.
  ///
  /// Throws [SrtException] if accept fails
  ///
  Future<SrtSocket> get accept async {
    _checkNotClosed();

    final data = await _asyncControl.getFisrt("Accept");
    final socket = SrtSocket.fromHandle(data);
    socket._asyncControl = SocketThread(socket);
    Srt.addSocket = socket;
    return socket;
  }

  /// Get transmission statistics for this socket
  ///
  /// This wraps the native [srt_bstats] function to return current
  /// performance metrics and statistics for the socket.
  ///
  /// [clear] if true, resets the statistics counters after retrieval
  ///
  /// Returns a [SocketStats] object containing transmission metrics like
  /// send/receive rates, packet loss, RTT, buffer usage, etc.
  ///
  /// Throws [SrtException] if stats retrieval fails
  ///
  SocketStats get statistics {
    _checkNotClosed();

    final perf = calloc<CBytePerfMon>();
    try {
      final result = Srt.bindings.srt_bstats(_socketHandle, perf, 1);

      checkSrtResult(result, operation: "get stats", handle: _socketHandle);

      return _statistics..updateFromNative(perf.ref);
    } finally {
      calloc.free(perf);
    }
  }

  /// Receive data from this socket in stream mode
  ///
  /// This wraps the native [srt_recv/srt_recvmsg] function and is suitable for
  /// continuous data reception. The data is read from a native buffer
  /// and converted to a Dart [Uint8List].
  ///
  /// Returns a [Uint8List] containing the received data. May be empty if
  /// the receive timeout expired. Returns fewer bytes than [bufferSize] if
  /// less data is available.
  ///
  /// Throws [SrtException] if receiving fails
  ///
  Future<Uint8List> get recvStream async {
    _checkNotClosed();

    final SrtMessage data = await _asyncControl.getFisrt("RecvMessage");
    return data.payload;
  }

  /// Receive a message from this socket
  ///
  /// This wraps the native [srt_recvmsg2] function to receive messages
  /// in message mode with control information.
  ///
  /// [bufferSize] is the maximum number of bytes to receive (default 1500)
  ///
  /// Returns an [SrtMessage] containing the payload and metadata.
  /// Returns a message with empty payload if the receive timeout expired.
  ///
  /// Throws [SrtException] if receiving fails
  ///
  Future<SrtMessage> get recvMessage async {
    _checkNotClosed();

    return await _asyncControl.getFisrt("RecvMessage");
  }

  /// Create a new SRT socket
  ///
  /// [options] can be used to pre-configure socket settings.
  /// If null, a live mode option is used.
  ///
  /// Throws [SrtException] if socket creation fails
  ///
  SrtSocket({this.options}) : _socketHandle = Srt.bindings.srt_create_socket() {
    checkSrtResult(
      _socketHandle,
      operation: 'create socket instance',
      handle: _socketHandle,
    );
    Srt.addSocket = this;

    // TODO: Register finalizer for automatic dispose

    options ??= SocketOptions.liveMode();

    options!.applyTo(_socketHandle);

    _asyncControl = SocketThread(this);
  }

  /// Bind this socket to the specified address and port
  ///
  /// This is typically called on the server side before [listen].
  ///
  /// [address] can be an IPv4/IPv6 InternetAddress (e.g., "127.0.0.1") or "0.0.0.0" for all interfaces
  /// [port] is the port number (1-65535)
  ///
  /// Throws [SrtException] if binding fails
  ///
  void bind(InternetAddress address, int port) {
    _checkNotClosed();

    final sockAddr = SrtAddress.fromInternetAddress(address, port);

    try {
      final size = address.type == InternetAddressType.IPv4
          ? ffi.sizeOf<sockaddr_in>()
          : ffi.sizeOf<sockaddr_in6>();
      final result = Srt.bindings.srt_bind(_socketHandle, sockAddr, size);
      checkSrtResult(
        result,
        operation: 'srt_bind(${address.address}:$port)',
        handle: _socketHandle,
      );
    } finally {
      calloc.free(sockAddr);
    }
  }

  /// Listen for incoming connections on this socket
  ///
  /// Must call [bind] before [listen]
  ///
  /// [backlog] specifies the maximum number of pending connections (default 1)
  ///
  /// Throws [SrtException] if listen fails
  ///
  ListenStats listen({int backlog = 1, AcceptConnectionCallback? onAccept}) {
    _checkNotClosed();

    final listenStats = ListenStats(onIncomingConnection: onAccept);

    if (status != SRT_SOCKSTATUS.SRTS_LISTENING) {
      /// TODO: [onAccept] optional callback to accept/reject connections
      ///
      /// Example:
      /// ```dart
      /// serverSocket.listen(
      ///   onAccept: (info) { /// information retrieved from client
      ///     print('Client from ${info.peerAddress}:${info.peerPort}');
      ///     print('Stream ID: ${info.streamId}');
      ///
      ///     // Return true to accept, false to reject
      ///     return info.peerAddress == '192.168.1.100';
      ///   }
      /// );
      /// ```

      /// if (onAccept != null) {
      ///
      ///   late ffi.NativeCallable callback;
      ///   callback = ffi.NativeCallable<SrtListenCallback>.isolateLocal(
      ///     listenStats.nativeRegisterAttempt,
      ///     exceptionalReturn: 0,
      ///   );
      ///
      ///   listenStats.nativeCallBack = callback;
      ///
      ///   final lcallbackResult = Srt.bindings.srt_listen_callback(
      ///     _socketHandle,
      ///     callback.nativeFunction.cast(),
      ///     ffi.nullptr,
      ///   );
      ///   checkSrtResult(lcallbackResult, operation: "srt_listen_callback", handle : _socketHandle);
      ///   print("the return $lcallbackResult, 0 == sucess");
      /// }

      _listen(backlog);
    }

    return listenStats;
  }

  void _listen(int backlog) {
    final result = Srt.bindings.srt_listen(_socketHandle, backlog);
    checkSrtResult(
      result,
      operation: 'srt_listen(backlog=$backlog)',
      handle: _socketHandle,
    );
  }

  /// Connect this socket to a remote InternetAddress
  ///
  /// [address] can be an IPv4/Ipv6 InternetAddress (e.g., "192.168.1.1" or "::1")
  /// [port] is the remote port number (1-65535)
  ///
  /// This is typically called on the client side. The local address is
  /// automatically bound to an ephemeral port.
  ///
  /// Throws [SrtException] if connection fails
  ///
  Future<void> connect(InternetAddress address, int port, [int wait = 100]) async {
    _checkNotClosed();
    if (status == SRT_SOCKSTATUS.SRTS_CONNECTED) return;

    await _asyncControl.getFisrt(
      "Connect",
      arg: SocketInterface(address, port),
    );
    if (wait > 0) {
      await Future.delayed(Duration(milliseconds: wait));
    }
  }

  /// Close this socket and release its resources
  ///
  /// After calling [dispose], this socket cannot be used anymore.
  /// Calling any other method will throw [StateError].
  ///
  /// Safe to call multiple times (subsequent calls are no-ops)
  ///
  void dispose() {
    if (_isClosed) return;

    _asyncControl.clean();

    final result = Srt.bindings.srt_close(_socketHandle);
    if (result != -1) {
      _isClosed = true;
    }
  }

  /// Internal: Create from an existing socket handle (for accept())
  SrtSocket.fromHandle(int handle)
    : _socketHandle = handle,
      options = SocketOptions();

  /// Check if socket is closed, throw if it is
  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('SrtSocket is closed and cannot be used');
    }
  }

  /// Send data over this socket in stream mode
  ///
  /// This wraps the native [srt_send] function and is suitable for
  /// continuous data transmission. The data is copied to a native buffer
  /// before transmission.
  ///
  /// [data] is the bytes to send.
  /// Need be less than or equal to the payload size ( defined in [options] ) or use the chanked behavior.
  ///
  /// [chunked] is a option for send data in multply packets.
  /// If enabled the recvStrem only can get one packet, so is recomended to use [waitStream].
  /// See the live_mode example.
  ///
  /// Returns the number of bytes actually sent.
  ///
  /// Throws [SrtException] if sending fails
  ///
  int sendStream(Uint8List data, {bool chunked = false}) {
    _checkNotClosed();

    if (status != SRT_SOCKSTATUS.SRTS_CONNECTED){
      return -1;
    }

    if (data.isEmpty) return 0;

    // Allocate native buffer and copy data
    final buffer = calloc<ffi.Char>(options!.payloadSize);
    try {
      // Copy data to native buffer
      for (int i = 0; i < min(options!.payloadSize, data.length); i++) {
        buffer[i] = data[i];
      }

      int bytesSent = Srt.bindings.srt_send(
        _socketHandle,
        buffer,
        options!.payloadSize,
      );

      if ((data.length - options!.payloadSize) > 0 && chunked) {
        final newData = data.sublist(options!.payloadSize, data.length);
        bytesSent += sendStream(newData, chunked: true);
      }

      checkSrtResult(bytesSent, operation: "send data", handle: _socketHandle);

      return bytesSent;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Send a message over this socket
  ///
  /// This wraps the native [srt_sendmsg2] function and allows sending
  /// messages with control information (TTL, in-order delivery, etc.)
  /// in message mode rather than stream mode.
  ///
  /// [text] is the message data to send
  /// [ttl] is the time-to-live in milliseconds (default -1 for infinite)
  /// [inOrder] specifies whether the message must arrive in order (default false)
  ///
  /// Returns the number of bytes actually sent.
  ///
  /// Throws [SrtException] if sending fails
  ///
  int sendMessage(
    String text, {
    MessageControl control = const MessageControl(),
  }) {
    _checkNotClosed();

    final payload = Uint8List.fromList(text.codeUnits);
    // Create and initialize message control structure
    final buffer = calloc<ffi.Char>(payload.length);
    final mctrl = control.toNative();

    try {
      // Initialize message control
      Srt.bindings.srt_msgctrl_init(mctrl);

      // Copy payload to native buffer
      for (int i = 0; i < payload.length; i++) {
        buffer[i] = payload[i];
      }

      final bytesSent = Srt.bindings.srt_sendmsg2(
        _socketHandle,
        buffer,
        payload.length,
        mctrl,
      );

      checkSrtResult(bytesSent, operation: "send a menssage, no bytes sended");

      return bytesSent;
    } finally {
      calloc.free(mctrl);
      calloc.free(buffer);
    }
  }

  /// Send a file over this socket
  ///
  /// This wraps the native [srt_sendfile] function and efficiently
  /// transmits a file by reading directly from disk without buffering
  /// the entire file in memory.
  ///
  /// Use the FileOptions class to set the path of output and others configuartions.
  ///
  /// Returns the number of bytes actually sent.
  ///
  /// Throws [SrtException] if the send fails or [ArgumentError] if the file doesn't exist
  ///
  Future<int> sendFile(FileOptions fileOtions) async {
    _checkNotClosed();

    await fileOtions.start();
    final int data = await _asyncControl.getFisrt("SendFile", arg: fileOtions);
    return data;
  }

  /// Receive a file over this socket
  ///
  /// This wraps the native [srt_recvfile] function and efficiently
  /// receives a file by writing directly to disk without buffering
  /// the entire file in memory.
  ///
  /// Use the FileOptions class to set the path of output and others configuartions.
  ///
  /// Returns the number of bytes actually received.
  ///
  /// The output file is created if it doesn't exist. If it exists,
  /// data is appended at the specified offset.
  ///
  /// Throws [SrtException] if the receive fails or if the parent directory doesn't exist
  ///
  Future<int> recvFile(FileOptions fileOtions) async {
    _checkNotClosed();

    await fileOtions.start();
    final int data = await _asyncControl.getFisrt("RecvFile", arg: fileOtions);
    return data;
  }

  /// Get the local address this socket is bound to
  ///
  /// This wraps [srt_getsockname] to retrieve the local socket address.
  ///
  /// Returns the local [InternetAddress] and port in a map: {'address': InternetAddress, 'port': int}
  ///
  /// Note: Only works for bound sockets (after bind() call)
  ///
  /// Throws [SrtException] if getsockname fails
  ///
  SocketInterface getLocalAddress() {
    _checkNotClosed();

    final addrStorage = calloc<sockaddr_storage>();
    final addrLen = calloc<ffi.Int>();
    try {
      addrLen.value = ffi.sizeOf<sockaddr_storage>();
      final addr = addrStorage.cast<sockaddr>();

      final result = Srt.bindings.srt_getsockname(_socketHandle, addr, addrLen);

      checkSrtResult(
        result,
        operation: "get socket name",
        handle: _socketHandle,
      );

      return SocketInterface(
        SrtAddress.retriveAddress(addr),
        SrtAddress.retrivePort(addr),
      );
    } finally {
      calloc.free(addrStorage);
      calloc.free(addrLen);
    }
  }

  /// Get the remote address this socket is connected to
  ///
  /// This wraps [srt_getpeername] to retrieve the peer socket address.
  ///
  /// Returns the remote [InternetAddress] and port in a map: {'address': InternetAddress, 'port': int}
  ///
  /// Note: Only works for connected sockets (after connect() call)
  ///
  /// Throws [SrtException] if getpeername fails or socket is not connected
  ///
  SocketInterface getRemoteAddress() {
    _checkNotClosed();

    final addrStorage = calloc<sockaddr_storage>();
    final addrLen = calloc<ffi.Int>();
    try {
      addrLen.value = ffi.sizeOf<sockaddr_storage>();
      final addr = addrStorage.cast<sockaddr>();

      final result = Srt.bindings.srt_getpeername(_socketHandle, addr, addrLen);

      checkSrtResult(result, operation: "get peer name", handle: _socketHandle);

      return SocketInterface(
        SrtAddress.retriveAddress(addr),
        SrtAddress.retrivePort(addr),
      );
    } finally {
      calloc.free(addrStorage);
      calloc.free(addrLen);
    }
  }

  int _acceptMethod() {
    final addrStorage = calloc<sockaddr_storage>();
    final addrLen = calloc<ffi.Int>();
    try {
      addrLen.value = ffi.sizeOf<sockaddr_storage>();

      /// TODO : Add especific address,
      /// TODO : Do the Isolte finish the accept
      ///

      final clientHandle = Srt.bindings.srt_accept(
        _socketHandle,
        addrStorage.cast<sockaddr>(),
        addrLen,
      );

      checkSrtResult(clientHandle, operation: 'accept', handle: _socketHandle);

      return clientHandle;

      // Create new socket wrapper with the accepted connection
    } finally {
      calloc.free(addrStorage);
      calloc.free(addrLen);
    }
  }

  SrtMessage _recvMessageMethod({int bufferSize = 1500}) {
    final buffer = calloc<ffi.Char>(bufferSize);
    final mctrl = calloc<SRT_MSGCTRL>();

    try {
      final bytesReceived = Srt.bindings.srt_recvmsg2(
        _socketHandle,
        buffer,
        bufferSize,
        mctrl,
      );

      checkSrtResult(
        bytesReceived,
        operation: "receive data from live mode",
        handle: _socketHandle,
      );

      final control = MessageControl.fromNative(mctrl.ref);

      final payload = Uint8List(bytesReceived);

      for (int i = 0; i < bytesReceived; i++) {
        payload[i] = buffer[i];
      }

      return SrtMessage(
        payload: payload,
        control: control,
        bytesReceived: bytesReceived,
      );
    } finally {
      calloc.free(buffer);
    }
  }

  int _recvFileMethod(FileOptions options) {
    final bytesReceived = Srt.bindings.srt_recvfile(
      _socketHandle,
      options.pathPtr.cast<ffi.Char>(),
      options.offsetPtr,
      options.size!,
      options.blockSize,
    );

    checkSrtResult(bytesReceived, operation: "receive a file");
    options.clean();

    return bytesReceived;
  }

  int _sendFileMethod(FileOptions options) {
    final bytesReceived = Srt.bindings.srt_sendfile(
      _socketHandle,
      options.pathPtr.cast<ffi.Char>(),
      options.offsetPtr,
      options.size!,
      options.blockSize,
    );

    checkSrtResult(bytesReceived, operation: "receive a file");
    options.clean();

    return bytesReceived;
  }

  int _connectMethod(SocketInterface iInterface) {
    final sockAddr = SrtAddress.fromInternetAddress(
      iInterface.ipAddress,
      iInterface.port,
    );
    try {
      final size = iInterface.ipAddress.type == InternetAddressType.IPv4
          ? ffi.sizeOf<sockaddr_in>()
          : ffi.sizeOf<sockaddr_in6>();
      final result = Srt.bindings.srt_connect(_socketHandle, sockAddr, size);
      checkSrtResult(
        result,
        operation: 'srt_connect($iInterface)',
        handle: _socketHandle,
      );

      return 0;
    } finally {
      calloc.free(sockAddr);
    }
  }
}

class SocketThread extends ThreadMananger {
  final SrtSocket socket;

  // TODO: Use Enum on masks

  SocketThread(this.socket) {
    masks['Accept'] = IsolateInfo(
      unique: false,
      action: socket._acceptMethod,
      // timeOut: socket.options?.acceptTimeout,
    );
    masks['Connect'] = IsolateInfo(
      unique: true,
      menssage: "You already connecting",
      action: socket._connectMethod,
      // timeOut: socket.options?.acceptTimeout,
    );
    masks['RecvMessage'] = IsolateInfo(
      unique: true,
      menssage: "You already waiting for data",
      action: socket._recvMessageMethod,
    );
    masks['RecvFile'] = IsolateInfo(
      unique: true,
      menssage: "You already waiting for a File",
      action: socket._recvFileMethod,
    );
    masks['SendFile'] = IsolateInfo(
      unique: true,
      menssage: "You already sending a File",
      action: socket._sendFileMethod,
    );
  }
}

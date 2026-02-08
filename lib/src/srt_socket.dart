import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'dart:io';
import 'package:srt_dart/src/options.dart';
import 'package:srt_dart/src/exceptions.dart';
import 'package:srt_dart/src/address.dart';
import 'package:srt_dart/src/message.dart';
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
/// // afterwards dispose the SRT library
/// *.dispose();
///
/// ```
class SrtSocket {
  /// The underlying FFI bindings

  /// The socket file descriptor from SRT
  late int _socketHandle;

  /// Whether this socket has been closed
  bool _isClosed = false;

  /// Get the current status of this socket
  ///
  /// Returns a [SRT_SOCKSTATUS] enum value indicating the socket state
  SRT_SOCKSTATUS get status => Srt.bindings.srt_getsockstate(_socketHandle);

  /// Check if this socket is currently closed
  bool get isClosed => _isClosed;

  /// Create a new SRT socket
  ///
  /// [options] can be used to pre-configure socket settings.
  /// If null, default options are used.
  ///
  /// Throws [SrtException] if socket creation fails
  SrtSocket({SocketOptions? options}) {
    _socketHandle = Srt.bindings.srt_create_socket();

    if (_socketHandle == -1) {
      throw SrtException.fromLastError(Srt.bindings);
    }

    // TODO: Register finalizer for automatic dispose

    // Apply options if provided
    if (options != null) {
      options.applyTo(_socketHandle, Srt.bindings);
    }
  }

  /// Bind this socket to the specified address and port
  ///
  /// This is typically called on the server side before [listen].
  ///
  /// [address] can be an IPv4 string (e.g., "127.0.0.1") or "0.0.0.0" for all interfaces
  /// [port] is the port number (1-65535)
  ///
  /// Throws [SrtException] if binding fails
  void bind(String address, int port) {
    _checkNotClosed();

    final sockAddr = SrtAddress.createIpv4Address(address, port, Srt.bindings);

    try {
      final result = Srt.bindings.srt_bind(
        _socketHandle,
        sockAddr,
        ffi.sizeOf<sockaddr_in>(),
      );

      checkSrtResult(
        result,
        Srt.bindings,
        operation: 'srt_bind($address:$port)',
      );
    } finally {
      calloc.free(sockAddr);
    }
  }

  /// Bind this socket to the specified InternetAddress and port
  ///
  /// This variant accepts Dart's [InternetAddress] for IPv4/IPv6 flexibility
  ///
  /// Throws [SrtException] if binding fails
  void bindAddress(InternetAddress address, int port) {
    _checkNotClosed();

    final sockAddr = SrtAddress.fromInternetAddress(
      address,
      port,
      Srt.bindings,
    );
    try {
      final size = address.type == InternetAddressType.IPv4
          ? ffi.sizeOf<sockaddr_in>()
          : ffi.sizeOf<sockaddr_in6>();
      final result = Srt.bindings.srt_bind(_socketHandle, sockAddr, size);
      checkSrtResult(
        result,
        Srt.bindings,
        operation: 'srt_bind(${address.address}:$port)',
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
  void listen({int backlog = 1}) {
    _checkNotClosed();

    final result = Srt.bindings.srt_listen(_socketHandle, backlog);
    checkSrtResult(
      result,
      Srt.bindings,
      operation: 'srt_listen(backlog=$backlog)',
    );
  }

  /// Accept an incoming connection on this socket
  ///
  /// Must call [listen] before [accept]
  ///
  /// This is a blocking operation. Returns a new [SrtSocket] representing
  /// the connected client.
  ///
  /// Throws [SrtException] if accept fails
  SrtSocket accept() {
    _checkNotClosed();

    final addrStorage = calloc<sockaddr_storage>();
    final addrLen = calloc<ffi.Int>();
    try {
      addrLen.value = ffi.sizeOf<sockaddr_storage>();

      final clientHandle = Srt.bindings.srt_accept(
        _socketHandle,
        addrStorage.cast<sockaddr>(),
        addrLen,
      );

      if (clientHandle == -1) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      // Create new socket wrapper with the accepted connection
      final clientSocket = SrtSocket._fromHandle(clientHandle);
      return clientSocket;
    } finally {
      calloc.free(addrStorage);
      calloc.free(addrLen);
    }
  }

  /// Connect this socket to a remote address
  ///
  /// [address] can be an IPv4 string (e.g., "192.168.1.1")
  /// [port] is the remote port number (1-65535)
  ///
  /// This is typically called on the client side. The local address is
  /// automatically bound to an ephemeral port.
  ///
  /// Throws [SrtException] if connection fails
  void connect(String address, int port) {
    _checkNotClosed();

    final sockAddr = SrtAddress.createIpv4Address(address, port, Srt.bindings);
    try {
      final result = Srt.bindings.srt_connect(
        _socketHandle,
        sockAddr,
        ffi.sizeOf<sockaddr_in>(),
      );
      checkSrtResult(
        result,
        Srt.bindings,
        operation: 'srt_connect($address:$port)',
      );
    } finally {
      calloc.free(sockAddr);
    }
  }

  /// Connect this socket to a remote InternetAddress
  ///
  /// This variant accepts Dart's [InternetAddress] for IPv4/IPv6 flexibility
  ///
  /// Throws [SrtException] if connection fails
  void connectAddress(InternetAddress address, int port) {
    _checkNotClosed();

    final sockAddr = SrtAddress.fromInternetAddress(
      address,
      port,
      Srt.bindings,
    );
    try {
      final size = address.type == InternetAddressType.IPv4
          ? ffi.sizeOf<sockaddr_in>()
          : ffi.sizeOf<sockaddr_in6>();
      final result = Srt.bindings.srt_connect(_socketHandle, sockAddr, size);
      checkSrtResult(
        result,
        Srt.bindings,
        operation: 'srt_connect(${address.address}:$port)',
      );
    } finally {
      calloc.free(sockAddr);
    }
  }

  /// Close this socket and release its resources
  ///
  /// After calling [dispose], this socket cannot be used anymore.
  /// Calling any other method will throw [StateError].
  ///
  /// Safe to call multiple times (subsequent calls are no-ops)
  void dispose() {
    if (_isClosed) return;

    final result = Srt.bindings.srt_close(_socketHandle);
    if (result != -1) {
      _isClosed = true;
    }
  }

  /// Internal: Create from an existing socket handle (for accept())
  SrtSocket._fromHandle(int handle) : _socketHandle = handle;

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
  /// [data] is the bytes to send
  ///
  /// Returns the number of bytes actually sent. May be less than the
  /// length of [data] if the send buffer is full.
  ///
  /// Throws [SrtException] if sending fails
  int sendStream(Uint8List data) {
    _checkNotClosed();

    if (data.isEmpty) return 0;

    // Allocate native buffer and copy data
    final buffer = calloc<ffi.Char>(data.length);
    try {
      // Copy data to native buffer
      for (int i = 0; i < data.length; i++) {
        buffer[i] = data[i];
      }

      final bytesSent = Srt.bindings.srt_send(_socketHandle, buffer, data.length);

      if (bytesSent < 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      return bytesSent;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Receive data from this socket in stream mode
  ///
  /// This wraps the native [srt_recv] function and is suitable for
  /// continuous data reception. The data is read from a native buffer
  /// and converted to a Dart [Uint8List].
  ///
  /// [bufferSize] is the maximum number of bytes to receive (default 1500)
  ///
  /// Returns a [Uint8List] containing the received data. May be empty if
  /// the receive timeout expired. Returns fewer bytes than [bufferSize] if
  /// less data is available.
  ///
  /// Throws [SrtException] if receiving fails
  Uint8List recvStream({int bufferSize = 1500}) {
    _checkNotClosed();

    final buffer = calloc<ffi.Char>(bufferSize);
    try {
      final bytesReceived = Srt.bindings.srt_recv(_socketHandle, buffer, bufferSize);

      if (bytesReceived < 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      if (bytesReceived == 0) {
        return Uint8List(0);
      }

      // Convert native buffer to Dart list
      final result = Uint8List(bytesReceived);
      for (int i = 0; i < bytesReceived; i++) {
        result[i] = buffer[i];
      }

      return result;
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
  int sendMessage(
    String text, {MessageControl control = const MessageControl()}) {
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

      if (bytesSent < 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      return bytesSent;
    } finally {
      calloc.free(mctrl);
      calloc.free(buffer);
    }
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
  SrtMessage recvMessage({int bufferSize = 1500}) {
    _checkNotClosed();

    final buffer = calloc<ffi.Char>(bufferSize);
    final mctrl = calloc<SRT_MSGCTRL>();

    try {
      // Initialize message control
      Srt.bindings.srt_msgctrl_init(mctrl);

      final bytesReceived = Srt.bindings.srt_recvmsg2(
        _socketHandle,
        buffer,
        bufferSize,
        mctrl,
      );

      if (bytesReceived < 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      // Convert native buffer to Dart list
      final payload = bytesReceived > 0
          ? Uint8List(bytesReceived)
          : Uint8List(0);

      for (int i = 0; i < bytesReceived; i++) {
        payload[i] = buffer[i];
      }

      // Create message control info from native structure
      final control = MessageControl.fromNative(mctrl.ref);

      return SrtMessage(
        payload: payload,
        control: control,
        bytesReceived: bytesReceived,
      );
    } finally {
      calloc.free(buffer);
      calloc.free(mctrl);
    }
  }
}

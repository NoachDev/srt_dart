import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'dart:io';
import 'package:srt_dart/src/options.dart';
import 'package:srt_dart/src/exceptions.dart';
import 'package:srt_dart/src/address.dart';
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
}

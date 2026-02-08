import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
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

  /// Send a file over this socket
  ///
  /// This wraps the native [srt_sendfile] function and efficiently
  /// transmits a file by reading directly from disk without buffering
  /// the entire file in memory.
  ///
  /// [filePath] is the path to the file to send
  /// [offset] is the file offset to start reading from (default 0)
  /// [size] is the number of bytes to send (default 0 = entire file from offset)
  /// [blockSize] is the read block size in bytes (default 262144 = 256KB)
  ///
  /// Returns the number of bytes actually sent. The size of a file
  /// transmission can be much larger than available system buffers,
  /// so multiple calls may be needed.
  ///
  /// Throws [SrtException] if the send fails or [ArgumentError] if the file doesn't exist
  int sendFile(
    String filePath, {
    int offset = 0,
    int size = 0,
    int blockSize = 262144,
  }) {
    _checkNotClosed();

    // Verify file exists
    final file = File(filePath);
    if (!file.existsSync()) {

      throw ArgumentError('File not found: $filePath');
    }

    if (offset < 0) {
      throw ArgumentError('Offset must be non-negative, got $offset');
    }

    if (blockSize <= 0) {
      throw ArgumentError('Block size must be positive, got $blockSize');
    }

    // Convert file path to native string
    final pathPtr = filePath.toNativeUtf8();
    // Offset needs to be a pointer to Int64
    final offsetPtr = calloc<ffi.Int64>();
    try {
      offsetPtr.value = offset;
      final actualSize = size <= 0 ? -1 : size;

      final bytesSent = Srt.bindings.srt_sendfile(
        _socketHandle,
        pathPtr.cast<ffi.Char>(),
        offsetPtr,
        actualSize,
        blockSize,
      );

      if (bytesSent < 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      return bytesSent;
    } finally {
      calloc.free(pathPtr);
      calloc.free(offsetPtr);
    }
  }

  /// Receive a file over this socket
  ///
  /// This wraps the native [srt_recvfile] function and efficiently
  /// receives a file by writing directly to disk without buffering
  /// the entire file in memory.
  ///
  /// [outputPath] is the path where the file will be saved
  /// [offset] is the file offset to start writing at (default 0)
  /// [size] is the number of bytes to receive
  /// [blockSize] is the write block size in bytes (default 262144 = 256KB)
  ///
  /// Returns the number of bytes actually received. The size of a file
  /// transmission can be much larger than available system buffers,
  /// so multiple calls may be needed.
  ///
  /// The output file is created if it doesn't exist. If it exists,
  /// data is appended at the specified offset.
  ///
  /// Throws [SrtException] if the receive fails or if the parent directory doesn't exist
  int recvFile(
    String outputPath, {
    int offset = 0,
    int size = 0,
    int blockSize = 262144,
  }) {
    _checkNotClosed();

    // Verify the parent directory exists
    final file = File(outputPath);
    final parent = file.parent;
    if (!parent.existsSync()) {
      throw ArgumentError('Parent directory does not exist: ${parent.path}');
    }

    if (offset < 0) {
      throw ArgumentError('Offset must be non-negative, got $offset');
    }

    if (blockSize <= 0) {
      throw ArgumentError('Block size must be positive, got $blockSize');
    }
    if (size <= 0) {
      throw ArgumentError('Size must be positive, got $size');
    }

    // Convert path to native string
    final pathPtr = outputPath.toNativeUtf8();
    // Offset needs to be a pointer to Int64
    final offsetPtr = calloc<ffi.Int64>();
    try {
      offsetPtr.value = offset;
      
      final bytesReceived = Srt.bindings.srt_recvfile(
        _socketHandle,
        pathPtr.cast<ffi.Char>(),
        offsetPtr,
        size,
        blockSize,
      );

      if (bytesReceived < 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      return bytesReceived;
    } finally {
      calloc.free(pathPtr);
      calloc.free(offsetPtr);
    }
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
  SocketStats getStats({bool clear = false}) {
    _checkNotClosed();

    final perf = calloc<CBytePerfMon>();
    try {
      final result = Srt.bindings.srt_bstats(
        _socketHandle,
        perf,
        clear ? 1 : 0,
      );

      if (result != 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      return SocketStats.fromNative(perf.ref);
    } finally {
      calloc.free(perf);
    }
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
  Map<String, dynamic> getLocalAddress() {
    _checkNotClosed();

    final addrStorage = calloc<sockaddr_storage>();
    final addrLen = calloc<ffi.Int>();
    try {
      addrLen.value = ffi.sizeOf<sockaddr_storage>();

      final result = Srt.bindings.srt_getsockname(
        _socketHandle,
        addrStorage.cast<sockaddr>(),
        addrLen,
      );

      if (result != 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      // Parse the address based on family
      final family = addrStorage.ref.ss_family;
      if (family == 2) { // AF_INET (IPv4)
        final addr = addrStorage.cast<sockaddr_in>();
        final s_addr = addr.ref.sin_addr.s_addr;
        
        // Convert to IP address string
        final octets = [
          (s_addr & 0xFF),
          ((s_addr >> 8) & 0xFF),
          ((s_addr >> 16) & 0xFF),
          ((s_addr >> 24) & 0xFF)
        ];
        final ipStr = octets.join('.');
        final port = _ntohs(addr.ref.sin_port);

        return {
          'address': InternetAddress(ipStr),
          'port': port,
        };
      }

      throw SrtException(
        'Unsupported address family: $family',
        errorCode: SRT_ERRNO.SRT_EINVOP.value,
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
  Map<String, dynamic> getRemoteAddress() {
    _checkNotClosed();

    final addrStorage = calloc<sockaddr_storage>();
    final addrLen = calloc<ffi.Int>();
    try {
      addrLen.value = ffi.sizeOf<sockaddr_storage>();

      final result = Srt.bindings.srt_getpeername(
        _socketHandle,
        addrStorage.cast<sockaddr>(),
        addrLen,
      );

      if (result != 0) {
        throw SrtException.fromLastError(Srt.bindings);
      }

      // Parse the address based on family
      final family = addrStorage.ref.ss_family;
      if (family == 2) { // AF_INET (IPv4)
        final addr = addrStorage.cast<sockaddr_in>();
        final s_addr = addr.ref.sin_addr.s_addr;
        
        // Convert to IP address string
        final octets = [
          (s_addr & 0xFF),
          ((s_addr >> 8) & 0xFF),
          ((s_addr >> 16) & 0xFF),
          ((s_addr >> 24) & 0xFF)
        ];
        final ipStr = octets.join('.');
        final port = _ntohs(addr.ref.sin_port);

        return {
          'address': InternetAddress(ipStr),
          'port': port,
        };
      }

      throw SrtException(
        'Unsupported address family: $family',
        errorCode: SRT_ERRNO.SRT_EINVOP.value,
      );
    } finally {
      calloc.free(addrStorage);
      calloc.free(addrLen);
    }
  }

  /// Helper function to convert network byte order to host byte order
  static int _ntohs(int value) {
    // Network byte order is big-endian, reverse the swap done by _htons
    return ((value & 0xFF) << 8) | ((value >> 8) & 0xFF);
  }
}

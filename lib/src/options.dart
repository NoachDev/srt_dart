import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:srt_dart/src/exceptions.dart';
import 'package:srt_dart/main.dart';

/// Socket option configuration for SRT sockets
///
/// This class provides a type-safe, fluent interface for configuring common
/// SRT socket options before connection.
class SocketOptions {
  /// Maximum Segment Size (in bytes)
  /// Default varies based on SRTO_TRANSTYPE
  int? mss;

  /// SRTO_TRANSTYPE: Data Transmission Type
  /// 0 = Live mode (SRTT_LIVE)
  /// 1 = File mode (SRTT_FILE)
  int? transType;

  /// SRTO_MESSAGEAPI: Enable SRT Message API
  /// When true, buffer is treated as one message (applies to srt_sendmsg/srt_recvmsg)
  bool? messageApi;

  /// SRTO_SENDER: Set socket as sender
  /// When true, socket acts as a LIVE sender
  bool? sender;

  /// SRTO_SNDTIMEO: Send timeout (milliseconds)
  /// Timeout for blocking send operations (null = blocking indefinitely)
  int? sendTimeout;

  /// SRTO_RCVTIMEO: Receive timeout (milliseconds)
  /// Timeout for blocking receive operations (null = blocking indefinitely)
  int? recvTimeout = 100;

  /// SRTO_CONNTIMEO: Receive timeout (milliseconds)
  /// Timeout for blocking connect operations (null = blocking indefinitely)
  int? connectTimeout = 100;

  /// Timeout for blocking accept operations (null = blocking indefinitely)
  int? acceptTimeout = 100;

  /// SRTO_REUSEADDR: Allow reuse of local address in TIME_WAIT state
  bool? reuseAddr;

  /// SRTO_MAXBW: Maximum bandwidth (bytes per second)
  /// 0 = unlimited, -1 = follow SRTO_INPUTBW
  int? maxBandwidth;

  /// SRTO_INPUTBW: Input bandwidth (bytes per second)
  /// Used to estimate the time needed to send data
  int? inputBandwidth;

  /// SRTO_OHEADROOM: Overhead for IP/UDP headers (bytes)
  /// Default is 28 bytes for IPv4
  int? overheadRoom;

  /// SRTO_PBKEYLEN: Encryption key length (bytes): 0 (no encryption), 16, 24, or 32
  int? encryptionKeyLength;

  /// SRTO_PASSPHRASE: Passphrase for encryption
  String? encryptionPassphrase;

  /// SRTO_PAYLOADSIZE: size of payload (bytes)
  /// 
  /// Is a value less then or equal to 1456.
  int payloadSize;

  late int _socketHandle;

  /// Creates a new SocketOptions with optional initial values
  SocketOptions({
    this.mss,
    this.transType,
    this.messageApi,
    this.sender,
    this.sendTimeout,
    this.recvTimeout,
    this.reuseAddr,
    this.maxBandwidth,
    this.inputBandwidth,
    this.overheadRoom,
    this.encryptionKeyLength,
    this.encryptionPassphrase,
    this.payloadSize = 1316,
  });

  /// Creates an options object optimized for live streaming
  factory SocketOptions.liveMode({bool sender = true}) => SocketOptions(
    transType: 0, // SRTT_LIVE
    sender: sender,
  );

  /// Creates an options object optimized for file transfer
  factory SocketOptions.fileMode({bool sender = true}) => SocketOptions(
    transType: 1, // SRTT_FILE
    sender: sender,
  );

  /// Creates an options object optimized for message-based communication
  factory SocketOptions.messageMode({bool sender = true}) =>
      SocketOptions(messageApi: true, sender: sender);

  /// Applies these options to an SRT socket
  ///
  /// This method sets all configured options on the given socket handle.
  /// Non-null options are applied with [srt_setsockopt].
  void applyTo(int socketHandle) {
    _socketHandle = socketHandle;

    if (payloadSize != 1316){
      payloadSize = min(payloadSize, 1456);
      _setSockOpt(SRT_SOCKOPT.SRTO_PAYLOADSIZE, payloadSize);
    }

    if (transType != null) {
      _setSockOpt(
        SRT_SOCKOPT.SRTO_TRANSTYPE,
        transType!,
      );
    }

    if (mss != null) {
      _setSockOpt(SRT_SOCKOPT.SRTO_MSS, mss!);
    }

    if (messageApi != null) {
      _setSockOptBool(
        SRT_SOCKOPT.SRTO_MESSAGEAPI,
        messageApi!,
      );
    }

    if (sender != null) {
      _setSockOptBool(SRT_SOCKOPT.SRTO_SENDER, sender!);
    }

    if (sendTimeout != null) {
      _setSockOpt(
        SRT_SOCKOPT.SRTO_SNDTIMEO,
        sendTimeout!,
      );
    }

    if (recvTimeout != null) {
      _setSockOpt(
        SRT_SOCKOPT.SRTO_RCVTIMEO,
        recvTimeout!,
      );
    }
    
    if (connectTimeout != null) {
      _setSockOpt(
        SRT_SOCKOPT.SRTO_CONNTIMEO,
        connectTimeout!,
      );
    }

    if (reuseAddr != null) {
      _setSockOptBool(
        SRT_SOCKOPT.SRTO_REUSEADDR,
        reuseAddr!,
      );
    }

    if (maxBandwidth != null) {
      _setSockOpt(
        SRT_SOCKOPT.SRTO_MAXBW,
        maxBandwidth!,
      );
    }

    if (inputBandwidth != null) {
      _setSockOpt(
        SRT_SOCKOPT.SRTO_INPUTBW,
        inputBandwidth!,
      );
    }

    if (overheadRoom != null) {
      _setSockOpt(
        SRT_SOCKOPT.SRTO_OHEADBW,
        overheadRoom!,
      );
    }

    if (encryptionKeyLength != null) {
      _setSockOpt(
        SRT_SOCKOPT.SRTO_PBKEYLEN,
        encryptionKeyLength!,
      );
    }

    if (encryptionPassphrase != null) {
      _setSockOptString(
        SRT_SOCKOPT.SRTO_PASSPHRASE,
        encryptionPassphrase!,
      );
    }
  }

  /// Internal: Set integer socket option
  void _setSockOpt(
    SRT_SOCKOPT option,
    int value,
  ) {
    final valuePtr = calloc<ffi.Int>();
    try {
      valuePtr.value = value;
      final result = Srt.bindings.srt_setsockflag(
        _socketHandle,
        option,
        valuePtr.cast<ffi.Void>(),
        ffi.sizeOf<ffi.Int>(),
      );
      checkSrtResult(result, operation: 'srt_setsockopt(${option.name})', handle : _socketHandle);
    } finally {
      calloc.free(valuePtr);
    }
  }

  /// Internal: Set boolean socket option
  void _setSockOptBool(
    SRT_SOCKOPT option,
    bool value,
  ) {
    final valuePtr = calloc<ffi.Int>();
    try {
      valuePtr.value = value ? 1 : 0;
      final result = Srt.bindings.srt_setsockflag(
        _socketHandle,
        option,
        valuePtr.cast<ffi.Void>(),
        ffi.sizeOf<ffi.Int>(),
      );
      checkSrtResult(result, operation: 'srt_setsockopt(${option.name})', handle : _socketHandle);
    } finally {
      calloc.free(valuePtr);
    }
  }

  /// Internal: Set string socket option (for passphrase, etc)
  void _setSockOptString(
    SRT_SOCKOPT option,
    String value,
  ) {
    final valuePtr = value.toNativeUtf8();
    try {
      final result = Srt.bindings.srt_setsockflag(
        _socketHandle,
        option,
        valuePtr.cast<ffi.Void>(),
        value.length,
      );
      checkSrtResult(result, operation: 'srt_setsockopt(${option.name})', handle : _socketHandle);
    } finally {
      calloc.free(valuePtr);
    }
  }
}

/// Configuartions for receiving or sending a file.
///
/// [path] is the path where the file will be saved
/// [offset] is the file offset to start writing at (default 0)
/// [size] is the number of bytes to receive
/// [blockSize] is the write block size in bytes (default 262144 = 256KB)
/// 
class FileOptions {
  final String path;
  final int offset;
  final int blockSize;

  int? size;

  late ffi.Pointer<Utf8> pathPtr;

  // Offset needs to be a pointer to Int64
  final offsetPtr = calloc<ffi.Int64>();

  FileOptions({
    required this.path,
    this.size,
    this.offset = 0,
    this.blockSize = 262144,
  }) : pathPtr = path.toNativeUtf8(); // Convert path to native string

  Future<void> start() async{
    try {
      await _checkOptions();
      offsetPtr.value = offset;
    } catch (e) {
      clean();
      rethrow;
    }
  }

  Future<void> _checkOptions() async {
    // Verify if the parent directory exists
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) {
      throw ArgumentError('Parent directory does not exist: ${parent.path}');
    }

    if (offset < 0) {
      throw ArgumentError('Offset must be non-negative, got $offset');
    }

    if (blockSize <= 0) {
      throw ArgumentError('Block size must be positive, got $blockSize');
    }
    
    size ??= await file.length();

    if (size! <= 0) {
      throw ArgumentError('Size must be positive, got $size');
    }
  }

  void clean() {
    calloc.free(pathPtr);
    calloc.free(offsetPtr);
  }
}

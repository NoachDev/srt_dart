import 'dart:ffi' as ffi;
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

  /// SRTO_RCVSYN: Receive in Synchronous Mode
  /// When true, srt_recv() will block until full buffer is received
  bool? recvSynchronous;

  /// SRTO_SNDSYN: Send in Synchronous Mode
  /// When true, srt_send() will block until the buffer is accepted by the transport layer
  bool? sendSynchronous;

  /// SRTO_SENDER: Set socket as sender
  /// When true, socket acts as a LIVE sender
  bool? sender;

  /// SRTO_SNDTIMEO: Send timeout (milliseconds)
  /// Timeout for blocking send operations (-1 = blocking indefinitely)
  int? sendTimeout;

  /// SRTO_RCVTIMEO: Receive timeout (milliseconds)
  /// Timeout for blocking receive operations (-1 = blocking indefinitely)
  int? recvTimeout;

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
    this.recvSynchronous,
    this.sendSynchronous,
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

    if (recvSynchronous != null) {
      _setSockOptBool(
        SRT_SOCKOPT.SRTO_RCVSYN,
        recvSynchronous!,
      );
    }

    if (sendSynchronous != null) {
      _setSockOptBool(
        SRT_SOCKOPT.SRTO_SNDSYN,
        sendSynchronous!,
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
      checkSrtResult(result, operation: 'srt_setsockopt(${option.name})');
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
      checkSrtResult(result, operation: 'srt_setsockopt(${option.name})');
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
      checkSrtResult(result, operation: 'srt_setsockopt(${option.name})');
    } finally {
      calloc.free(valuePtr);
    }
  }
}

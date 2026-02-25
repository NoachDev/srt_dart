import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:ffi/ffi.dart';

/// Control information for SRT messages
///
/// Wraps the native SRT_MSGCTRL structure and provides
/// type-safe access to message metadata and flags.
class MessageControl {
  /// Flags for the message
  final int flags;

  /// Time To Live for this message (in milliseconds)
  final int ttl;

  /// Whether the message should arrive in order (1) or not (0)
  final bool inOrder;

  /// Message boundary flag (1 = boundary, 0 = not boundary)
  final bool boundary;

  /// Source time (in microseconds since epoch)
  final int sourceTime;

  /// Packet sequence number
  final int packetSequence;

  /// Message sequence number
  final int messageNumber;

  /// Create a new MessageControl instance
  ///
  /// Default values:
  /// - flags: 0 (no flags)
  /// - ttl: -1 (infinite)
  /// - inOrder: false - 0 (may be out of order)
  /// - boundary: 0 (not a boundary)
  const MessageControl({
    this.flags = 0,
    this.ttl = -1,
    this.inOrder = false,
    this.boundary = false,
    this.sourceTime = 0,
    this.packetSequence = 0,
    this.messageNumber = 0,
  });

  /// Create a MessageControl from a native SRT_MSGCTRL structure
  factory MessageControl.fromNative(SRT_MSGCTRL native) {
    return MessageControl(
      flags: native.flags,
      ttl: native.msgttl,
      inOrder: native.inorder == 1,
      boundary: native.boundary == 1,
      sourceTime: native.srctime,
      packetSequence: native.pktseq,
      messageNumber: native.msgno,
    );
  }

  /// Convert this MessageControl to a native SRT_MSGCTRL structure
  ///
  Pointer<SRT_MSGCTRL> toNative() {
    final mctrl = calloc<SRT_MSGCTRL>();

    // Set message control parameters
    mctrl.ref.msgttl = ttl;
    mctrl.ref.inorder = inOrder ? 1 : 0;
    mctrl.ref.boundary = boundary ? 1 : 0;
    mctrl.ref.srctime = sourceTime;
    /// TODO: Register finalizer for automatic free
    return mctrl;
  }

  @override
  String toString() {
    return 'MessageControl(flags=$flags, ttl=$ttl, inOrder=$inOrder, '
        'boundary=$boundary, sourceTime=$sourceTime, '
        'packetSequence=$packetSequence, messageNumber=$messageNumber)';
  }
}

/// Represents an SRT message with payload and metadata
///
/// Used by [SrtSocket.recvMessage] to return both data and control information.
class SrtMessage {
  /// The message payload
  final Uint8List payload;

  /// Control information for this message
  final MessageControl control;

  /// The number of bytes actually received
  final int bytesReceived;

  /// The time where the menssage is received ( the SrtMessage is created )
  final DateTime timestamp;

  /// Get the message payload as a UTF-8 string
  String get text => String.fromCharCodes(payload);

  /// Create a new SrtMessage
  SrtMessage({
    required this.payload,
    required this.control,
    required this.bytesReceived,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'SrtMessage(bytesReceived=$bytesReceived, control=$control, '
        'payloadSize=${payload.length})';
  }

}

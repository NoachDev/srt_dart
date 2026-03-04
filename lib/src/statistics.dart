import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:srt_dart/src/address.dart';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:srt_dart/src/srt_socket.dart';

/// High-level wrapper around SRT transmission statistics (SRT_TRACEBSTATS)
///
/// Provides easy access to socket performance metrics for monitoring
/// data transfer progress and diagnosing network issues.
class SocketStats {
  /// Timestamp when these statistics were collected (milliseconds)
  int msTimeStamp;

  /// Total packets sent
  int pktSentTotal;

  /// Total packets received
  int pktRecvTotal;

  /// Total packets lost on send
  int pktSndLossTotal;

  /// Total packets lost on receive
  int pktRcvLossTotal;

  /// Total packets retransmitted
  int pktRetransTotal;

  /// Total bytes sent
  int byteSentTotal;

  /// Total bytes received
  int byteRecvTotal;

  /// Current send rate in Mbps
  double mbpsSendRate;

  /// Current receive rate in Mbps
  double mbpsRecvRate;

  /// Round trip time in milliseconds
  double msRTT;

  /// Available bandwidth in Mbps
  double mbpsBandwidth;

  /// Packets in send buffer
  int pktSndBuf;

  /// Bytes in send buffer
  int byteSndBuf;

  /// Packets in receive buffer
  int pktRcvBuf;

  /// Bytes in receive buffer
  int byteRcvBuf;

  int byteSentUniqueTotal;

  int _recvPointer = 0;

  int get recvPointer => _recvPointer;

  void addToPointer() {
    _recvPointer++;
  }

  /// Create a new SocketStats
  SocketStats({
    this.msTimeStamp = 0,
    this.pktSentTotal = 0,
    this.pktRecvTotal = 0,
    this.pktSndLossTotal = 0,
    this.pktRcvLossTotal = 0,
    this.pktRetransTotal = 0,
    this.byteSentTotal = 0,
    this.byteRecvTotal = 0,
    this.mbpsSendRate = 0,
    this.mbpsRecvRate = 0,
    this.msRTT = 0,
    this.mbpsBandwidth = 0,
    this.pktSndBuf = 0,
    this.byteSndBuf = 0,
    this.pktRcvBuf = 0,
    this.byteRcvBuf = 0,
    this.byteSentUniqueTotal = 0,
  });

  /// Create SocketStats from native SRT_TRACEBSTATS structure
  void updateFromNative(CBytePerfMon stats) {
    msTimeStamp = stats.msTimeStamp;
    pktSentTotal = stats.pktSentTotal;
    pktRecvTotal = stats.pktRecvTotal;
    pktSndLossTotal = stats.pktSndLossTotal;
    pktRcvLossTotal = stats.pktRcvLossTotal;
    pktRetransTotal = stats.pktRetransTotal;
    byteSentTotal = stats.byteSentTotal;
    byteRecvTotal = stats.byteRecvTotal;
    mbpsSendRate = stats.mbpsSendRate;
    mbpsRecvRate = stats.mbpsRecvRate;
    msRTT = stats.msRTT;
    mbpsBandwidth = stats.mbpsBandwidth;
    pktSndBuf = stats.pktSndBuf;
    byteSndBuf = stats.byteSndBuf;
    // pktRcvBuf = max(0, stats.pktRcvBuf - _recvPointer);
    pktRcvBuf = stats.pktRcvBuf;
    byteRcvBuf = stats.byteRcvBuf;
    byteSentUniqueTotal = stats.byteSentUniqueTotal;
  }

  /// Calculate packet loss ratio as a percentage
  ///
  /// Returns 0.0 if no packets have been sent, otherwise returns
  /// the percentage of packets lost out of total sent.
  double getPacketLossRatio() {
    if (pktSentTotal == 0) return 0.0;
    return (pktSndLossTotal / pktSentTotal) * 100.0;
  }

  /// Check if connection quality is degraded
  ///
  /// Returns true if packet loss ratio exceeds 5% or RTT is very high
  bool isDegraded({double maxLossPercent = 5.0, double maxRttMs = 500.0}) {
    return getPacketLossRatio() > maxLossPercent || msRTT > maxRttMs;
  }

  /// Get formatted statistics summary
  String get formattedSummary =>
      '''SocketStats {
  Timestamp: ${msTimeStamp}ms
  Send Rate: ${mbpsSendRate.toStringAsFixed(2)} Mbps
  Recv Rate: ${mbpsRecvRate.toStringAsFixed(2)} Mbps
  RTT: ${msRTT.toStringAsFixed(2)}ms
  Available BW: ${mbpsBandwidth.toStringAsFixed(2)} Mbps
  Packets Sent: $pktSentTotal (Loss: $pktSndLossTotal, ${getPacketLossRatio().toStringAsFixed(2)}%)
  Packets Recv: $pktRecvTotal (Loss: $pktRcvLossTotal)
  Bytes Sent: $byteSentTotal
  Bytes Recv: $byteRecvTotal
  Send Buffer: $byteSndBuf bytes ($pktSndBuf packets)
  Recv Buffer: $byteRcvBuf bytes ($pktRcvBuf packets)
}''';

  @override
  String toString() => formattedSummary;
}

/// Callback function type for accepting/rejecting connections
///
/// Return true to accept the connection, false to reject it.
///
typedef AcceptConnectionCallback = bool Function(IncomingConnectionInfo info);

typedef SrtListenCallback =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int,
      ffi.Int,
      ffi.Pointer<sockaddr>,
      ffi.Pointer<ffi.Char>,
    );

/// Information about an incoming connection attempt
///
/// [socketHandle] The new socket handle created for this connection on the callback thread
/// [peerAddress] The IP address of the peer attempting to connect
/// [handshakeVersion] The SRT handshake version used by the peer
/// [streamId] The stream ID provided by the peer (can be empty)
/// [receivedAt] Timestamp when this connection was received
///
class IncomingConnectionInfo {
  final SrtSocket socketHandle;
  final InternetAddress peerAddress;
  final int handshakeVersion;
  final String streamId;
  final DateTime receivedAt;

  IncomingConnectionInfo({
    required this.socketHandle,
    required this.peerAddress,
    required this.handshakeVersion,
    required this.streamId,
  }) : receivedAt = DateTime.now();

  @override
  String toString() =>
      'IncomingConnection(socket=$socketHandle, peer=$peerAddress, streamId="$streamId", hs=$handshakeVersion)';
}

/// Class to monitoring the conections of a SRT listener
///
/// [connectionAttempts] Map of all incoming connection attempts and whether they were accepted
/// [onIncomingConnection] User-defined callback to determine if a connection should be accepted
///
class ListenStats {
  final Map<IncomingConnectionInfo, bool> connectionAttempts = {};
  late ffi.NativeCallable<Function> nativeCallBack;

  AcceptConnectionCallback? onIncomingConnection;

  ListenStats({this.onIncomingConnection});

  /// Internal method to register an incoming connection
  ///
  /// When a callback ( onAccept ) is seted in the listen function
  /// this method will be called by the native code and execute them
  ///
  int nativeRegisterAttempt(
    ffi.Pointer<ffi.Void> opaq,
    int ns,
    int hsversion,
    ffi.Pointer<sockaddr> peeraddr,
    ffi.Pointer<ffi.Char> streamid,
  ) {
    final stream = streamid == ffi.nullptr
        ? ''
        : streamid.cast<Utf8>().toDartString();

    final info = IncomingConnectionInfo(
      socketHandle: SrtSocket.fromHandle(ns),
      peerAddress: SrtAddress.retriveAddress(peeraddr),
      handshakeVersion: hsversion,
      streamId: stream,
    );

    final accepted = onIncomingConnection!(info);
    connectionAttempts[info] = accepted;

    return accepted ? 1 : 0;
  }

  /// Get connection attempts from a specific IP address
  List<IncomingConnectionInfo> getAttemptsFromIp(String ip) {
    return connectionAttempts.keys
        .where((attempt) => attempt.peerAddress.address == ip)
        .toList();
  }

  /// Get accepted connections
  List<IncomingConnectionInfo> getAcceptedConnections() {
    return connectionAttempts.keys
        .where((attempt) => connectionAttempts[attempt]!)
        .toList();
  }

  /// Get rejected connections
  List<IncomingConnectionInfo> getRejectedConnections() {
    return connectionAttempts.keys
        .where((attempt) => !connectionAttempts[attempt]!)
        .toList();
  }

  @override
  String toString() {
    final accepted = getAcceptedConnections().length;
    final rejected = getRejectedConnections().length;
    return 'ListenStats(total=$connectionAttempts.length, accepted=$accepted, rejected=$rejected)';
  }
}

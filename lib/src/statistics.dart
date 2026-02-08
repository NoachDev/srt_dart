import 'package:srt_dart/src/bindings/srt_bindings.dart';

/// High-level wrapper around SRT transmission statistics (SRT_TRACEBSTATS)
///
/// Provides easy access to socket performance metrics for monitoring
/// data transfer progress and diagnosing network issues.
class SocketStats {
  /// Timestamp when these statistics were collected (milliseconds)
  final int msTimeStamp;

  /// Total packets sent
  final int pktSentTotal;

  /// Total packets received
  final int pktRecvTotal;

  /// Total packets lost on send
  final int pktSndLossTotal;

  /// Total packets lost on receive
  final int pktRcvLossTotal;

  /// Total packets retransmitted
  final int pktRetransTotal;

  /// Total bytes sent
  final int byteSentTotal;

  /// Total bytes received
  final int byteRecvTotal;

  /// Current send rate in Mbps
  final double mbpsSendRate;

  /// Current receive rate in Mbps
  final double mbpsRecvRate;

  /// Round trip time in milliseconds
  final double msRTT;

  /// Available bandwidth in Mbps
  final double mbpsBandwidth;

  /// Packets in send buffer
  final int pktSndBuf;

  /// Bytes in send buffer
  final int byteSndBuf;

  /// Packets in receive buffer
  final int pktRcvBuf;

  /// Bytes in receive buffer
  final int byteRcvBuf;

  final int byteSentUniqueTotal;

  /// Create a new SocketStats
  SocketStats({
    required this.msTimeStamp,
    required this.pktSentTotal,
    required this.pktRecvTotal,
    required this.pktSndLossTotal,
    required this.pktRcvLossTotal,
    required this.pktRetransTotal,
    required this.byteSentTotal,
    required this.byteRecvTotal,
    required this.mbpsSendRate,
    required this.mbpsRecvRate,
    required this.msRTT,
    required this.mbpsBandwidth,
    required this.pktSndBuf,
    required this.byteSndBuf,
    required this.pktRcvBuf,
    required this.byteRcvBuf,
    required this.byteSentUniqueTotal,
  });

  /// Create SocketStats from native SRT_TRACEBSTATS structure
  factory SocketStats.fromNative(CBytePerfMon stats) {
    return SocketStats(
      msTimeStamp: stats.msTimeStamp,
      pktSentTotal: stats.pktSentTotal,
      pktRecvTotal: stats.pktRecvTotal,
      pktSndLossTotal: stats.pktSndLossTotal,
      pktRcvLossTotal: stats.pktRcvLossTotal,
      pktRetransTotal: stats.pktRetransTotal,
      byteSentTotal: stats.byteSentTotal,
      byteRecvTotal: stats.byteRecvTotal,
      mbpsSendRate: stats.mbpsSendRate,
      mbpsRecvRate: stats.mbpsRecvRate,
      msRTT: stats.msRTT,
      mbpsBandwidth: stats.mbpsBandwidth,
      pktSndBuf: stats.pktSndBuf,
      byteSndBuf: stats.byteSndBuf,
      pktRcvBuf: stats.pktRcvBuf,
      byteRcvBuf: stats.byteRcvBuf,
      byteSentUniqueTotal: stats.byteSentUniqueTotal,
    );
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

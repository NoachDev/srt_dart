import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:io';
import 'package:srt_dart/src/bindings/srt_bindings.dart';
import 'package:srt_dart/srt_dart.dart';

/// Standard POSIX socket address family constants
abstract class AddressFamily {
  static const int unspecified = 0;
  static const int inet = 2; // IPv4
  static const int inet6 = 10; // IPv6
}

interface class SocketInterface {
  final InternetAddress ipAddress;
  final int port;

  SocketInterface(this.ipAddress, this.port);

  @override
  String toString() {
    // TODO: implement toString
    return "ip : [ ${ipAddress.address} ] port : [ $port ]";
  }
}

const int _inetAddrsTrLen = 16; // includes terminating NUL
const int _inet6AddrsTrLen = 46; // includes terminating NUL

/// Helper utilities for creating socket addresses (sockaddr structures)
class SrtAddress {
  /// Creates a sockaddr_in structure for IPv4 addresses
  ///
  /// [hostAddress] can be an IPv4 address string (e.g., "127.0.0.1")
  /// [port] is the port number (0-65535)
  ///
  /// Returns a pointer to sockaddr suitable for srt_bind/srt_connect
  static ffi.Pointer<sockaddr> createIpv4Address(String hostAddress, int port) {
    if (port < 0 || port > 65535) {
      throw ArgumentError('Port must be between 0 and 65535, got $port');
    }

    // Allocate and initialize sockaddr_in structure
    final addr = calloc<sockaddr_in>();

    try {
      addr.ref.sin_family = AddressFamily.inet;
      addr.ref.sin_port = htons(port);

      // Convert IP string to binary using inet_pton
      final hostPtr = hostAddress.toNativeUtf8();
      try {
        // Get pointer to sin_addr for inet_pton to write to
        // sin_addr is located after sin_family and sin_port
        final sinAddrPtr =
            (addr.cast<ffi.Uint8>() +
                    ffi.sizeOf<sa_family_t>() +
                    ffi.sizeOf<in_port_t>())
                .cast<in_addr>();

        final result = Srt.bindings.inet_pton(
          AddressFamily.inet,
          hostPtr.cast<ffi.Char>(),
          sinAddrPtr.cast<ffi.Void>(),
        );

        if (result != 1) {
          throw ArgumentError('Invalid IPv4 address: $hostAddress');
        }
      } finally {
        calloc.free(hostPtr);
      }

      // Zero-fill sin_zero padding
      for (int i = 0; i < 8; i++) {
        addr.ref.sin_zero[i] = 0;
      }

      return addr.cast<sockaddr>();
    } catch (e) {
      calloc.free(addr);
      rethrow;
    }
  }

  /// Creates a sockaddr_in6 structure for IPv6 addresses
  ///
  /// [hostAddress] can be an IPv6 address string (e.g., "::1" or "fe80::1")
  /// [port] is the port number (0-65535)
  /// [flowInfo] is the flow information (typically 0)
  /// [scopeId] is the scope ID for link-local addresses (typically 0)
  ///
  /// Returns a pointer to sockaddr suitable for srt_bind/srt_connect
  static ffi.Pointer<sockaddr> createIpv6Address(
    String hostAddress,
    int port, {
    int flowInfo = 0,
    int scopeId = 0,
  }) {
    if (port < 0 || port > 65535) {
      throw ArgumentError('Port must be between 0 and 65535, got $port');
    }

    // Allocate and initialize sockaddr_in6 structure
    final addr = calloc<sockaddr_in6>();

    try {
      addr.ref.sin6_family = AddressFamily.inet6;
      addr.ref.sin6_port = htons(port);
      addr.ref.sin6_flowinfo = flowInfo;
      addr.ref.sin6_scope_id = scopeId;

      // Convert IP string to binary using inet_pton
      final hostPtr = hostAddress.toNativeUtf8();
      try {
        // Get pointer to sin6_addr for inet_pton to write to
        // sin6_addr is located after sin6_family, sin6_port, and sin6_flowinfo
        final sin6AddrPtr =
            (addr.cast<ffi.Uint8>() +
                    ffi.sizeOf<sa_family_t>() +
                    ffi.sizeOf<in_port_t>() +
                    ffi.sizeOf<ffi.Uint32>())
                .cast<in6_addr>();

        final result = Srt.bindings.inet_pton(
          AddressFamily.inet6,
          hostPtr.cast<ffi.Char>(),
          sin6AddrPtr.cast<ffi.Void>(),
        );

        if (result != 1) {
          throw ArgumentError('Invalid IPv6 address: $hostAddress');
        }
      } finally {
        calloc.free(hostPtr);
      }

      return addr.cast<sockaddr>();
    } catch (e) {
      calloc.free(addr);
      rethrow;
    }
  }

  static int retrivePort(ffi.Pointer<sockaddr> addrPtr) {
    final family = addrPtr.ref.sa_family;
    
    switch (family) {
      case AddressFamily.inet:
        final addr = addrPtr.cast<sockaddr_in>();
        // The port from srt_getsockname is in htons format, apply htons again to convert back
        return htons(addr.ref.sin_port);

      case AddressFamily.inet6:
        final addr = addrPtr.cast<sockaddr_in6>();
        // The port from srt_getsockname is in htons format, apply htons again to convert back
        return htons(addr.ref.sin6_port);

      default:
        throw SrtException(
          'Unsupported address family: $family',
          errorCode: SRT_ERRNO.SRT_EINVOP.value,
        );
    }
  }

  static String retriveIpV4Address(ffi.Pointer<sockaddr> addrPtr) {
    final inAddrPtr =
        (addrPtr.cast<ffi.Uint8>() +
                ffi.sizeOf<sa_family_t>() +
                ffi.sizeOf<in_port_t>())
            .cast<in_addr>();

    final hostPtr = calloc<ffi.Char>(_inetAddrsTrLen);
    try {
      final res = Srt.bindings.inet_ntop(
        AddressFamily.inet,
        inAddrPtr.cast<ffi.Void>(),
        hostPtr.cast<ffi.Char>(),
        _inetAddrsTrLen,
      );

      checkSrtResult(
        res.address,
        nonexpected: 0,
        operation: "inet_ntop failed for IPv4",
      );

      return hostPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(hostPtr);
    }
  }

  static String retriveIpV6Address(ffi.Pointer<sockaddr> addrPtr) {
    // IPv6: sin6_addr is located after sa_family, sin6_port and sin6_flowinfo
    final in6AddrPtr =
        (addrPtr.cast<ffi.Uint8>() +
                ffi.sizeOf<sa_family_t>() +
                ffi.sizeOf<in_port_t>() +
                ffi.sizeOf<ffi.Uint32>())
            .cast<in6_addr>();

    final hostPtr = calloc<ffi.Char>(_inet6AddrsTrLen);
    try {
      final res = Srt.bindings.inet_ntop(
        AddressFamily.inet6,
        in6AddrPtr.cast<ffi.Void>(),
        hostPtr.cast<ffi.Char>(),
        _inet6AddrsTrLen,
      );

      checkSrtResult(
        res.address,
        nonexpected: 0,
        operation: "inet_ntop failed for IPv6",
      );

      return hostPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(hostPtr);
    }
  }

  static InternetAddress retriveAddress(ffi.Pointer<sockaddr> addrPtr) {
    final family = addrPtr.ref.sa_family;

    switch (family) {
      case AddressFamily.inet:
        return InternetAddress(
          retriveIpV4Address(addrPtr),
          type: InternetAddressType.IPv4,
        );
      case AddressFamily.inet6:
        return InternetAddress(
          retriveIpV6Address(addrPtr),
          type: InternetAddressType.IPv6,
        );
      default:
        throw SrtException(
          'Unsupported address family: $family',
          errorCode: SRT_ERRNO.SRT_EINVOP.value,
        );
    }
  }

  /// Creates a sockaddr from an InternetAddress and port
  ///
  /// This is a convenience method that automatically detects IPv4 vs IPv6
  static ffi.Pointer<sockaddr> fromInternetAddress(
    InternetAddress address,
    int port,
  ) {
    switch (address.type) {
      case InternetAddressType.IPv4:
        return createIpv4Address(address.address, port);
      case InternetAddressType.IPv6:
        return createIpv6Address(address.address, port);
      default:
        throw UnsupportedError('Unsupported address type: ${address.type}');
    }
  }

  /// Helper function to convert host byte order to network byte order (big-endian)
  /// This is used for the port number in address structures
  static int htons(int value) {
    // Network byte order is big-endian
    // Swap bytes from host byte order (usually little-endian on x86/x64)
    return ((value & 0xFF) << 8) | ((value >> 8) & 0xFF);
  }
}

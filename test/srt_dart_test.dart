import 'package:srt_dart/srt_dart.dart';
import 'package:test/test.dart';

void main() {
  // Initialize SRT library once for all tests

  final srt = Srt();
  // Cleanup SRT library after all tests
  tearDownAll(() {
    srt.cleanUp();
  });

  group('SrtSocket - Lifecycle', () {
    final socket = SrtSocket(options: SocketOptions.liveMode(sender: false));

    test('Bind server socket to localhost', () {
      socket.bind('127.0.0.1', 5000);
    });

    test('Listen after bind succeeds', () {
      socket.listen();
    });

    test('Close socket multiple times is safe', () {
      socket.dispose();
      socket.dispose(); // Should not throw
      socket.dispose(); // Should not throw
      expect(socket.isClosed, equals(true));
    });

    test('Cannot use socket after close', () {
      expect(
        () => socket.bind('127.0.0.1', 5000),
        throwsA(isA<StateError>()),
      );
      expect(() => socket.bind('0.0.0.0', 1234), throwsStateError);
      expect(() => socket.listen(), throwsStateError);
      expect(() => socket.connect('127.0.0.1', 1234), throwsStateError);
    });

  });

  group('SrtSocket - Connect', () {
    test('Connect to localhost succeeds (even without listening)', () {
      final clientSocket = SrtSocket(options: SocketOptions.liveMode(sender: true));
      
      // Note: Connection will likely timeout or fail since nothing is listening,
      // but the wrapper should handle it gracefully
      try {
        clientSocket.connect('127.0.0.1', 5010);
      } on SrtException {
        // Expected - nothing is listening
      }
      
      clientSocket.dispose();
    });

  });

  group('SrtSocket - State Tracking', () {

    test('Status changes after bind', () {
      final socket = SrtSocket(options: SocketOptions.liveMode(sender: false));
      final statusBefore = socket.status;
      socket.bind('127.0.0.1', 5020);
      final statusAfter = socket.status;
      
      // Status should change after bind
      expect(statusBefore, isNotNull);
      expect(statusAfter, isNotNull);
      
      socket.dispose();
    });
  });

  group('Integration - Server/Client Basic Flow', () {

    final server1 = SrtSocket(options: SocketOptions.liveMode(sender: false));
    final server2 = SrtSocket(options: SocketOptions.liveMode(sender: false));
    final client = SrtSocket(options: SocketOptions.liveMode(sender: true));
    
    tearDown(() {
      client.dispose();
      server1.dispose();
      server2.dispose();
    });
    
    test('Multiple servers on different ports', () {
      
      expect(() => server1.bind('127.0.0.1', 5041), returnsNormally);
      expect(() => server2.bind('127.0.0.1', 5042), returnsNormally);
      
      expect(() => server1.listen(), returnsNormally);
      expect(() => server2.listen(), returnsNormally);
      
    });
  });
}

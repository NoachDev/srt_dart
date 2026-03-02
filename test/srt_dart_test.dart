import 'dart:io';

import 'package:srt_dart/srt_dart.dart';
import 'package:test/test.dart';

void main() {
  // Initialize SRT library once for all tests

  Srt();
  // Cleanup SRT library after all tests
  tearDownAll(() {
    Srt.cleanUp();
  });

  group('SrtSocket - Lifecycle', () {
    final socket1 = SrtSocket();
    final socket2 = SrtSocket();
    final socket3 = SrtSocket();
    final socket4 = SrtSocket();
    final socket5 = SrtSocket();
    final socket6 = SrtSocket();

    final statusBeforeListen = socket1.status;

    test('Connect without a listener got a timeout', () {
      expect(
        () => socket2.connect(InternetAddress.loopbackIPv4, 5000),
        throwsA(isA<SrtException>()),
      );
    });

    test('Connot listen before bind', () {
      expect(() => socket1.listen(), throwsA(isA<SrtException>()));
    });

    test('Bind multiply sockets into localhost', () {
      socket1.bind(InternetAddress.loopbackIPv4, 5000);
      socket3.bind(InternetAddress.loopbackIPv4, 5001);
    });

    test('Listen after bind succeeds', () {
      socket1.listen(backlog: 3);
      socket3.listen();
    });

    test('Status changes after listen', () {
      expect(statusBeforeListen, isNotNull);
      expect(socket1.status, SRT_SOCKSTATUS.SRTS_LISTENING);
    });

    test('Connot connect before listen/bind', () {
      expect(() => socket1.connect(InternetAddress.loopbackIPv4, 5001), throwsA(isA<SrtException>()));
    });

    test('Multiply connects in a same server and connect after listen succeeds', () {
      socket2.connect(InternetAddress.loopbackIPv4, 5000);
      socket4.connect(InternetAddress.loopbackIPv4, 5000);
      socket5.connect(InternetAddress.loopbackIPv4, 5000);
    });

    test("Can`t connect with more than alowed by backlog", (){
      expect(
        () => socket6.connect(InternetAddress.loopbackIPv4, 5000), throwsA(isA<SrtException>()));
    });
    
    test("Accept multiple connections", () async{
      
      final [handle1, handle2, handle3]  = await Future.wait([socket1.accept, socket1.accept, socket1.accept]);

      expect(handle1.getRemoteAddress().port, isNotNull);
      expect(handle2.getRemoteAddress().port, isNotNull);
      expect(handle3.getRemoteAddress().port, isNotNull);
    });

    test('Close socket multiple times is safe', () {
      socket1.dispose();
      socket2.dispose();
      socket3.dispose();
      socket1.dispose(); // Should not throw
      socket1.dispose(); // Should not throw
      expect(socket1.isClosed, equals(true));
    });

    test('Cannot use socket after close', () {
      expect(
        () => socket1.bind(InternetAddress.loopbackIPv4, 5000),
        throwsA(isA<StateError>()),
      );
      expect(
        () => socket1.bind(InternetAddress.anyIPv4, 1234),
        throwsStateError,
      );
      expect(() => socket1.listen(), throwsStateError);
      expect(
        () => socket1.connect(InternetAddress.loopbackIPv4, 1234),
        throwsStateError,
      );
    });
  });

}

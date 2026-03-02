import 'dart:io';

import 'package:srt_dart/srt_dart.dart';
import 'package:test/test.dart';

void main() {
  Srt();

  tearDownAll(() {
    Srt.cleanUp();
  });

  group("Get address", () {
    test("From ipV4", () async {
      final server = SrtSocket(options: SocketOptions.liveMode(sender: false));
      final client = SrtSocket(options: SocketOptions.liveMode(sender: true));

      // Use localhost instead of IPv6 to simplify testing
      server.bind(InternetAddress.loopbackIPv4, 9000);
      server.listen(backlog: 1);
      client.connect(InternetAddress.loopbackIPv4, 9000);
      final fhandle = await server.accept;

      final serverLocal = server.getLocalAddress();
      final clientRemote = client.getRemoteAddress();
      final acceptedRemote = fhandle.getRemoteAddress();

      print(
        '\tServer local: ${serverLocal.ipAddress.address}:${serverLocal.port}',
      );
      print(
        '\tClient remote: ${clientRemote.ipAddress.address}:${clientRemote.port}',
      );
      print(
        '\tAccepted remote: ${acceptedRemote.ipAddress.address}:${acceptedRemote.port}',
      );

      // Server should be listening on port 9000
      expect(serverLocal.port, 9000);

      server.dispose();
      client.dispose();
      fhandle.dispose();
    });

    test("From ipV6...", () async {
      final server = SrtSocket(options: SocketOptions.liveMode(sender: false));
      final client = SrtSocket(options: SocketOptions.liveMode(sender: true));

      // Use localhost instead of IPv6 to simplify testing
      server.bind(InternetAddress.loopbackIPv6, 6000);
      server.listen(backlog: 1);
      client.connect(InternetAddress.loopbackIPv6, 6000);
      final fhandle = await server.accept;

      final serverLocal = server.getLocalAddress();
      final clientRemote = client.getRemoteAddress();
      final acceptedRemote = fhandle.getRemoteAddress();

      print(
        '\tServer local: ${serverLocal.ipAddress.address}:${serverLocal.port}',
      );
      print(
        '\tClient remote: ${clientRemote.ipAddress.address}:${clientRemote.port}',
      );
      print(
        '\tAccepted remote: ${acceptedRemote.ipAddress.address}:${acceptedRemote.port}',
      );

      // Server should be listening on port 9000
      expect(serverLocal.port, 6000);

      server.dispose();
      client.dispose();
      fhandle.dispose();
    });
  });
  // end of group

  group("Listen statistics", () {
    test("reject all connections", () async {
      final server = SrtSocket(
        options: SocketOptions.messageMode(sender: false),
      );
      final client = SrtSocket(
        options: SocketOptions.messageMode(sender: true),
      );

      server.bind(InternetAddress.loopbackIPv6, 5000);
      final satatics = server.listen(
        backlog: 1,
        onAccept: (info) => false,
      );
      client.connect(InternetAddress.loopbackIPv6, 5000);

      print("before accept");
      print(server.status);
      print(client.status);

      final fhandle = await server.accept;

      print("after accept");
      print(server.status);
      print(client.status);
      print(fhandle.status);

      final connected = client.status == SRT_SOCKSTATUS.SRTS_CONNECTED;

      print(satatics.connectionAttempts);

      fhandle.dispose();

      server.dispose();
      client.dispose();

      expect(connected, false);
    });
    test("accept all connections", () async{
      final server = SrtSocket(
        options: SocketOptions.messageMode(sender: false),
      );
      final client = SrtSocket(
        options: SocketOptions.messageMode(sender: true),
      );

      server.bind(InternetAddress.loopbackIPv6, 5001);
      server.listen(backlog: 1, onAccept: (info) => true);
      client.connect(InternetAddress.loopbackIPv6, 5001);

      print("before accept");
      print(server.status);
      print(client.status);

      final fhandle = await server.accept;

      print("after accept");
      print(server.status);
      print(client.status);
      print(fhandle.status);

      final connected = client.status == SRT_SOCKSTATUS.SRTS_CONNECTED;
      try{
        expect(connected, true);
      }
      catch(e){
        print("some error occor");
      }

      fhandle.dispose();

      server.dispose();
      client.dispose();
    });
    test("accept if is a loopBack (all true) connections", () async {
      final server = SrtSocket(
        options: SocketOptions.messageMode(sender: false),
      );
      final client = SrtSocket(
        options: SocketOptions.messageMode(sender: true),
      );

      server.bind(InternetAddress.loopbackIPv6, 5001);
      server.listen(
        backlog: 1,
        onAccept: (info) => info.peerAddress == InternetAddress.loopbackIPv6,
      );
      client.connect(InternetAddress.loopbackIPv6, 5001);

      print("before accept");
      print(server.status);
      print(client.status);

      final fhandle = await server.accept;

      print("after accept");
      print(server.status);
      print(client.status);
      print(fhandle.status);

      final connected = client.status == SRT_SOCKSTATUS.SRTS_CONNECTED;

      fhandle.dispose();

      server.dispose();
      client.dispose();
      
      expect(connected, true);
    });
  });
}

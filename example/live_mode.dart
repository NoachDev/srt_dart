import 'dart:io';
import 'dart:typed_data';

import 'package:srt_dart/srt_dart.dart';

/// Example demonstrating the Foundation & Core Wrapper functionality
/// 
/// In this example is created two sockets, one to receive data [serverSocket], and one to send data [clientSocket].
///
/// After the main partices (steps 1,2,3,4,5,7), of you can learnig more in [example/foundation] or in [README]
/// 
/// On step 6.
/// A data with two Strings [firstPayload], [lastPayload], and a "empety" list with 1289 zeros is sended - this overflow the UDP package capacity forcing the chunked mode be executed.
/// 
/// After send the data, the [waitAsStream] of epoll will notify when has a icoming data, and print them with the custumized menssage.
///  
void main() async {
  print('=== SRT Dart : Chunked mode + Epoll ===\n');

  // Initialize the SRT library (required first step)
  print('1. Initializing SRT library...');
  Srt();
  print('   ✓ SRT library initialized\n');

  // Create server socket with live mode configuration
  print('2. Creating server socket...');
  final serverSocket = SrtSocket();
  late SrtSocket handle;
  print('   ✓ Server socket created');
  print('   Status: ${serverSocket.status.name}\n');

  // Create client socket
  print('3. Creating client socket...');
  final clientSocket = SrtSocket();
  print('   ✓ Client socket created');
  print('   Status: ${clientSocket.status.name}\n');

  // Bind and listen server socket
  print('4. Server setup ...');
  serverSocket.bind(InternetAddress.loopbackIPv4, 9000);
  print('   ✓ Server bound to 127.0.0.1:9000');

  serverSocket.listen(backlog: 1);
  print('   ✓ Server listening\n');

  // Attempt client connection
  print('5. Connect and accept.');
  clientSocket.connect(InternetAddress.loopbackIPv4, 9000);
  print('   ✓ Client will connect');

  handle = await serverSocket.accept;
  print('   ✓ Server accepted connection\n');

  print('   Client Status: ${clientSocket.status.name}');
  print('   Server Status: ${serverSocket.status.name}\n');

  print('6. Send and Receive data and Using the Epoll for know when are incoming...');

  final epoll = SrtEpoll();
  epoll.register(handle, events: [EpollEventType.read]);

  final firstPayload = "A new menssage are incoming";
  final lastPayload = "Use the menssage Api";

  final fistsBytes = firstPayload.codeUnits;
  final lestsBytes = lastPayload.codeUnits;
  final middleBytes = List.generate(1316 - firstPayload.codeUnits.length, (elm) => 0);
  
  Future.delayed(Duration(seconds: 1), (){
    clientSocket.sendStream(Uint8List.fromList([...fistsBytes, ...middleBytes, ...lestsBytes]), chunked: true);
    print('sended');
  });

  epoll.timeOutMs = 1010;

  await for (final event in epoll.waitStream()){
    print("getting the message");
    final receivedMessage = await event.socket.recvStream; /// as the handle is the unique scoket registred, event.socket == handle
    print('Received message: ${String.fromCharCodes(receivedMessage)}');
  }


  // Cleanup
  epoll.dispose();
  print('\n7. Cleaning up resources...');
  clientSocket.dispose();
  print('   ✓ Client socket closed');
  serverSocket.dispose();
  print('   ✓ Server socket closed');
  // handle.dispose();
  print('   ✓ handle closed');
  Srt.cleanUp();
  print('   ✓ SRT library cleaned up\n');

}

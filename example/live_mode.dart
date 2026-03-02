import 'dart:io';
import 'dart:typed_data';

import 'package:srt_dart/srt_dart.dart';

/// Example demonstrating the Foundation & Core Wrapper functionality
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

  print('6. Send and Receive data...');
  final firstPayload = "A new menssage are incoming";
  final lastPayload = "Use the menssage Api";

  final fistsBytes = firstPayload.codeUnits;
  final lestsBytes = lastPayload.codeUnits;
  final middleBytes = List.generate(1316 - firstPayload.codeUnits.length, (elm) => 0);
  
  clientSocket.sendStream(Uint8List.fromList([...fistsBytes, ...middleBytes, ...lestsBytes]), chunked: true);

  final receivedMessage = await handle.recvStream;
  final receivedMessage2 = await handle.recvStream;

  print('   Received message: ${String.fromCharCodes(receivedMessage)}');
  print('   Received message: ${String.fromCharCodes(receivedMessage2)}\n');

  // Cleanup
  print('7. Cleaning up resources...');
  clientSocket.dispose();
  print('   ✓ Client socket closed');
  serverSocket.dispose();
  print('   ✓ Server socket closed');
  handle.dispose();
  print('   ✓ handle closed');
  Srt.cleanUp();
  print('   ✓ SRT library cleaned up\n');

}

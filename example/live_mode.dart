import 'dart:io';
import 'dart:typed_data';

import 'package:srt_dart/srt_dart.dart';

/// Example demonstrating the Foundation & Core Wrapper functionality
/// 
void main() async {
  print('=== SRT Dart : Chunked mode ===\n');

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
  print('6. Client attempting connection to 127.0.0.1:9000...');
  clientSocket.connect(InternetAddress.loopbackIPv4, 9000);
  print('   ✓ Client connected');
  handle = await serverSocket.accept();
  print('   ✓ Server accepted connection\n');

  print('   Client Status: ${clientSocket.status.name}');
  print('   Server Status: ${serverSocket.status.name}\n');

  print('7. Send and Receive data...');
  final firstPayload = "A new menssage are incoming";
  final lastPayload = "Hello World";

  final fistsBytes = firstPayload.codeUnits;
  final lestsBytes = lastPayload.codeUnits;
  final middleBytes = List.generate(1316 - firstPayload.codeUnits.length, (elm) => 0);
  
  // clientSocket.sendStream(Uint8List.fromList(payload.codeUnits);
  clientSocket.sendStream(Uint8List.fromList([...fistsBytes, ...middleBytes, ...lestsBytes]), chunked: true);
  final receivedMessage = handle.recvStream(-1);
  final receivedMessage2 = handle.recvStream(-1);

  print('   Received message: ${String.fromCharCodes(receivedMessage)}');
  print('   Received message: ${String.fromCharCodes(receivedMessage2)}\n');

  // Cleanup
  print('8. Cleaning up resources...');
  clientSocket.dispose();
  print('   ✓ Client socket closed');
  serverSocket.dispose();
  print('   ✓ Server socket closed');
  handle.dispose();
  print('   ✓ handle closed');
  Srt.cleanUp();
  print('   ✓ SRT library cleaned up\n');

}

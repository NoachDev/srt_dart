import 'dart:io';

import 'package:srt_dart/srt_dart.dart';

/// Example demonstrating the Foundation & Core Wrapper functionality
/// 
void main() async {
  print('=== SRT Dart : Foundation Layer Demo ===\n');

  // Initialize the SRT library (required first step)
  print('1. Initializing SRT library...');
  Srt();
  print('   ✓ SRT library initialized\n');

  // Create server socket with live mode configuration
  print('2. Creating server socket...');
  final menssageServerSocket = SrtSocket(options: SocketOptions.messageMode(sender: true));
  late SrtSocket fhandle;
  print('   ✓ Server socket created');
  print('   Status: ${menssageServerSocket.status.name}\n');

  // Create client socket
  print('3. Creating client socket...');
  final menssageClientSocket = SrtSocket(options: SocketOptions.messageMode(sender: true));
  print('   ✓ Client socket created');
  print('   Status: ${menssageClientSocket.status.name}\n');

  // Bind and listen server socket
  print('4. Server setup ...');
  menssageServerSocket.bind(InternetAddress.loopbackIPv4, 9000);
  print('   ✓ Server bound to 127.0.0.1:9000');

  menssageServerSocket.listen(backlog: 1);
  print('   ✓ Server listening\n');

  // Attempt client connection
  print('6. Client attempting connection to 127.0.0.1:9000...');
  menssageClientSocket.connect(InternetAddress.loopbackIPv4, 9000);
  print('   ✓ Client connected');
  fhandle = await menssageServerSocket.accept;
  print('   ✓ Server accepted connection');
  print('   Client Status: ${menssageClientSocket.status.name}');
  print('   Server Status: ${menssageServerSocket.status.name}\n');

  print('7. Message Mode Demo (sendMessage/recvMessage)...');
  print('   Creating message payload...');
  final messagePayload = "Hello World";
  print('   Payload: $messagePayload');
  
  print('   Testing sendMessage with metadata...');
  final bytesSent = menssageClientSocket.sendMessage(
    messagePayload,
    control: MessageControl(inOrder: true, ttl: 5000)
  );
  print('   ℹ Would send $bytesSent bytes with:');
  print('     - TTL: 5000ms');
  print('     - In-order: true (forces message arrival order)\n');

  print("8. Message received in server");
  final receivedMessage = await fhandle.recvMenssage;
  print('   Received message: ${receivedMessage.text}');
  print('   Metadata: ${receivedMessage.control}\n');

  print("9. The server will resend the message to confirm with the client");
  fhandle.sendMessage(receivedMessage.text, control: MessageControl(inOrder: true, ttl: 5000));
  final therc = await menssageClientSocket.recvMenssage;
  print('   The menssage received in the server is iqual the client : ${receivedMessage.text == therc.text}\n');

  // Cleanup
  print('10. Cleaning up resources...');
  menssageClientSocket.dispose();
  print('   ✓ Client socket closed');
  menssageServerSocket.dispose();
  print('   ✓ Server socket closed');
  fhandle.dispose();
  print('   ✓ handle closed');
  Srt.cleanUp();
  print('   ✓ SRT library cleaned up\n');

}

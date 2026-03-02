import 'dart:io';

import 'package:srt_dart/srt_dart.dart';

/// Example demonstrating the Foundation & Core Wrapper functionality
/// 
/// On the step 1, is initialized the SRT library.
/// This is fundamental and necessary for the good execution of the SRT.
/// And not needed called again.
/// 
/// On step 2 and 3, is created two sockets in message mode, [serverSocket], and [clientSocket], both with capacity to send data.
/// 
/// On step 4, the [serverSocket] is "binded" - configureted to listeng in the ip "127.0.0.1" (the loopBack) and in the port 9000.
/// And activing listen for a incoming connection with the [listen] method.
/// 
/// On step 5, the [messageClientSocket] will [connect] with the server for that the ip and port, of server, is passed into the function.
/// And the server [accept] the connection.
/// 
/// On step 6, a message is sended from the client to server - for large datas use the sendStream with chunked mode, and receive with the recvMessage or recvStream ( both work ).
/// 
/// On step 7, the message is received on server and decodified to a string with [.text] method
/// 
/// The step 8 is same of step 6, but the sender is the [serverSocket]  
/// 
/// On step 9, the sockets is [dispose] and the SRT [cleanUp] - an important step on workflow of the library.
/// 
void main() async {
  print('=== SRT Dart : Foundation Layer Demo ===\n');

  // Initialize the SRT library (required first step)
  print('1. Initializing SRT library...');
  Srt();
  print('   ✓ SRT library initialized\n');

  // Create server socket with live mode configuration
  print('2. Creating server socket...');
  final messageServerSocket = SrtSocket(options: SocketOptions.messageMode(sender: true));
  late SrtSocket fhandle;
  print('   ✓ Server socket created');
  print('   Status: ${messageServerSocket.status.name}\n');

  // Create client socket
  print('3. Creating client socket...');
  final messageClientSocket = SrtSocket(options: SocketOptions.messageMode(sender: true));
  print('   ✓ Client socket created');
  print('   Status: ${messageClientSocket.status.name}\n');

  // Bind and listen server socket
  print('4. Server setup ...');
  messageServerSocket.bind(InternetAddress.loopbackIPv4, 9000);
  print('   ✓ Server bound to 127.0.0.1:9000');

  messageServerSocket.listen(backlog: 1);
  print('   ✓ Server listening\n');

  // Attempt client connection
  print('5. Client attempting connection to 127.0.0.1:9000...');
  messageClientSocket.connect(InternetAddress.loopbackIPv4, 9000);
  print('   ✓ Client connected');
  fhandle = await messageServerSocket.accept;
  print('   ✓ Server accepted connection');
  print('   Client Status: ${messageClientSocket.status.name}');
  print('   Server Status: ${messageServerSocket.status.name}\n');

  print('6. Message Mode Demo (sendMessage/recvMessage)...');
  print('   Creating message payload...');
  final messagePayload = "Hello World";
  print('   Payload: $messagePayload');
  
  print('   Testing sendMessage with metadata...');
  final bytesSent = messageClientSocket.sendMessage(
    messagePayload,
    control: MessageControl(inOrder: true, ttl: 5000)
  );
  print('   ℹ Would send $bytesSent bytes with:');
  print('     - TTL: 5000ms');
  print('     - In-order: true (forces message arrival order)\n');

  print("7. Menssage received in server");
  final receivedMessage = await fhandle.recvMessage;
  print('   Received message: ${receivedMessage.text}');
  print('   Metadata: ${receivedMessage.control}\n');

  print("8. The server will resend the message to confirm with the client");
  fhandle.sendMessage(receivedMessage.text, control: MessageControl(inOrder: true, ttl: 5000));
  final therc = await messageClientSocket.recvMessage;
  print('   The message received in the server is iqual the client : ${receivedMessage.text == therc.text}\n');

  // Cleanup
  print('9. Cleaning up resources...');
  messageClientSocket.dispose();
  print('   ✓ Client socket closed');
  messageServerSocket.dispose();
  print('   ✓ Server socket closed');
  fhandle.dispose();
  print('   ✓ handle closed');
  Srt.cleanUp();
  print('   ✓ SRT library cleaned up\n');

}

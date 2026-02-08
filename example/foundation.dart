import 'package:srt_dart/srt_dart.dart';

/// Example demonstrating the Foundation & Core Wrapper functionality
/// 
void main() {
  print('=== SRT Dart : Foundation Layer Demo ===\n');

  // Initialize the SRT library (required first step)
  print('1. Initializing SRT library...');
  final srt = Srt();
  print('   ✓ SRT library initialized\n');

  // Create server socket with live mode configuration
  print('2. Creating server socket...');
  final menssageServerSocket = SrtSocket(options: SocketOptions.messageMode(sender: false));
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
  menssageServerSocket.bind('127.0.0.1', 9000);
  print('   ✓ Server bound to 127.0.0.1:9000');

  menssageServerSocket.listen(backlog: 1);
  print('   ✓ Server listening\n');

  // Attempt client connection
  print('6. Client attempting connection to 127.0.0.1:9000...');
  menssageClientSocket.connect('127.0.0.1', 9000);
  print('   ✓ Client connected');
  fhandle = menssageServerSocket.accept();
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
  final receivedMessage = fhandle.recvMessage();
  print('   Received message: ${receivedMessage.text}');
  print('   Metadata: ${receivedMessage.control}\n');

  // Demonstrate MessageControl builder pattern
  // Cleanup
  print('9. Cleaning up resources...');
  menssageClientSocket.dispose();
  print('   ✓ Client socket closed');
  menssageServerSocket.dispose();
  print('   ✓ Server socket closed');
  fhandle.dispose();
  print('   ✓ handle closed');
  srt.cleanUp();
  print('   ✓ SRT library cleaned up\n');

}

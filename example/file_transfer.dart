import 'dart:io';
import 'package:srt_dart/srt_dart.dart';
import 'dart:isolate';

/// Example demonstrating the File Transfer mode & Statistics
///
/// This example shows:
/// 1. File mode socket configuration
/// 2. File transfer operations (sendFile/recvFile)
/// 3. Statistics collection and monitoring
/// 4. Address information retrieval
/// 5. Transfer progress tracking
void main() async {
  print('=== SRT Dart : File Transfer & Statistics Demo ===\n');

  // Initialize the SRT library
  print('1. Initializing SRT library...');
  Srt();
  print('   ✓ SRT library initialized\n');

  // Create file mode sockets
  print('2. Creating file mode sockets...');
  final senderOptions = SocketOptions.fileMode(sender: true);
  final senderSocket = SrtSocket(options: senderOptions);

  final receiverOptions = SocketOptions.fileMode(sender: false);
  final receiverSocket = SrtSocket(options: receiverOptions);
  print('   ✓ File mode sockets created\n');

  // Setup server
  print('3. Setup ...');
  receiverSocket.bind(InternetAddress.loopbackIPv4, 9200);
  receiverSocket.listen(backlog: 1);
  print('   ✓ Server bound to 127.0.0.1:9200');

  senderSocket.connect(InternetAddress.loopbackIPv4, 9200);
  final fileHandle = await receiverSocket.accept();
  print('   ✓ Server setup complete\n');

  print('4. Starting file transfer in Isolate prcesses ...\n');
  final receiverPort = ReceivePort();
  final senderPort = ReceivePort();

  await Isolate.spawn((port) => _receiverTask(fileHandle, port), receiverPort.sendPort);
  await Isolate.spawn((port) => _senderTask(senderSocket, port), senderPort.sendPort);

  await receiverPort.first;
  await senderPort.first;
  
  // Cleanup
  print('5. Cleaning up resources...');
  senderSocket.dispose();
  print('   ✓ Sender socket closed');
  receiverSocket.dispose();
  print('   ✓ Receiver socket closed');
  // fileHandle.dispose();
  print('   ✓ File handle closed');
  Srt.cleanUp();
  print('   ✓ SRT library cleaned up\n');
}

void _receiverTask(SrtSocket socket, SendPort port) async {
  print('4.1 (receiver) Clean the temp directory ...');
  
  final tempDir = Directory.systemTemp;
  final sampleFile = File('${tempDir.path}/sample_transfer.png');
  
  if (sampleFile.existsSync()) {
    sampleFile.deleteSync();
  }

  print('   ✓ Temp directory cleaned\n');

  print('4.2 (receiver) Receive the file ...');
  
  // in real word this size should be known through metadata exchange such like recvStream and sendStream
  socket.recvFile(sampleFile.path, size: 4202339);

  if (sampleFile.existsSync()) {
    final fileSize = sampleFile.lengthSync();
    print('\n   ✓ File written successfully: $fileSize bytes\n');
  }

  // socket.dispose();

  port.send(null);

}

void _senderTask(SrtSocket socket, SendPort port) async {
  await Future.delayed(Duration(microseconds: 100)); // Ensure sender is ready

  print('4.1 (sender) Get the file to send ...');

  final sourceFile = File('example/file/a_cut_cat.png');
  if (!sourceFile.existsSync()) {
    print('   ✗ Source file not found: ${sourceFile.path}');
    return;
  }
  
  print('   ✓ Source file found: ${sourceFile.path}\n');

  // print("4.2 (sender) Send Metadata...");
  
  socket.sendFile('example/file/a_cut_cat.png');
  
  final fileByte = File('example/file/a_cut_cat.png').lengthSync();
  
  while (true) {
    final stats = socket.getStats();
    final percent = stats.byteSentUniqueTotal / fileByte * 100;
    stdout.write('\r Client Progress: ${percent.toStringAsFixed(2)}%');
    
    if (percent >= 100.0) {
      break;
    }
    
    sleep(Duration(milliseconds: 100));
  }
  print("");

  port.send(null);
  
}

import 'dart:io';
import 'package:srt_dart/srt_dart.dart';

/// Example demonstrating the File Transfer mode & Statistics
///
/// In this example is created two sockets, one to receive data [receiverSocket], and one to send data [senderSocket].
/// 
/// After the main partices (steps 1,2,3 and 6), of you can learnig more in [example/foundation] or in [README]
///
/// On step 4, a file located in the folder [file] is sended to the [receiverSocket]
/// 
/// On step 5, the file sended from [senderSocket] is storaged in the temp directory, for that he is clened ( a possible preview file [sample_transfer] is deleted ).
/// 
void main() async {
  print('=== SRT Dart : File Transfer & Statistics Demo ===\n');

  // Initialize the SRT library
  print('1. Initializing SRT library...');
  Srt();
  print('\t✓ SRT library initialized\n');

  // Create file mode sockets
  print('2. Creating file mode sockets...');
  final senderOptions = SocketOptions.fileMode(sender: true);
  final senderSocket = SrtSocket(options: senderOptions);

  final receiverOptions = SocketOptions.fileMode(sender: false);
  final receiverSocket = SrtSocket(options: receiverOptions);
  print('\t✓ File mode sockets created\n');

  // Setup server
  print('3. Setup ...');
  receiverSocket.bind(InternetAddress.loopbackIPv4, 9200);
  receiverSocket.listen(backlog: 1);
  print('\t✓ Server bound to 127.0.0.1:9200');

  senderSocket.connect(InternetAddress.loopbackIPv4, 9200);
  final fileHandle = await receiverSocket.accept;
  print('\t✓ Server setup complete\n');

  print("4. Send the file file/a_cut_cat.png ...\n");
  final sendfile = senderSocket.sendFile(FileOptions(path: "example/file/a_cut_cat.png"));

  print(
    "5. Receive the file in the temp directory ...",
  );
  print('\t5.1 Remove a older file in the temp directory ...');

  final tempDir = Directory.systemTemp;
  final sampleFile = File('${tempDir.path}/sample_transfer.png');

  if (sampleFile.existsSync()) {
    sampleFile.deleteSync();
  }

  print('\t\t✓ Temp directory cleaned');

  print('\t5.2 (receiver) Receive the file ...\n');

  /// in a real word application this size should be known through metadata exchange such like recvStream and sendStream
  final recvfile = fileHandle.recvFile(
    FileOptions(path: sampleFile.path, size: 4202339),
  );

  await Future.wait([sendfile, recvfile]);

  print('\t✓ File written successfully in ${sampleFile.path}\n');

  // Cleanup
  print('6. Cleaning up resources...');
  senderSocket.dispose();
  print('   ✓ Sender socket closed');
  receiverSocket.dispose();
  print('   ✓ Receiver socket closed');
  // fileHandle.dispose();
  print('   ✓ File handle closed');
  Srt.cleanUp();
  print('   ✓ SRT library cleaned up\n');
}

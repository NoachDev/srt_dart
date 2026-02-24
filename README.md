**Welcome to the Secure Reliable Transport wrapper for Dart**

SRT is a high-level protocol for streaming data with security and integrity. Primarily made in C/C++, see the [Haivision SRT repository](https://github.com/Haivision/srt).

The current library consumes the raw code and provides a Dart-like interface with sugar on top.

## First Steps:

### In a Dart environment
The `libsrt` package is required if you want to use the `srt_dart` with pure Dart. Follow the SRT [Build Documentation](https://github.com/Haivision/srt/tree/master/docs#build-instructions) for more details.

In Flutter apps this step is unnecessary. And, enusure to have the srt_flutter_libs in your pubspec.yaml

#### For Linux / Brew
```bash
  git clone https://github.com/Haivision/srt.git
  cd srt 
  ./configure
  make install
```

### Main pratices
In the head of project initilize the Srt class. He is the core and need be static on code. And, call the function cleanUp on finalize

After initlized or cleaned, don`t call Srt again

You can crete multiply sockets, such that needed call dispose on fineshed the main propoese of them

On necessary, the Epoll class can manage **100+** sockets

Built on the UDP protocol, the transport is done using a server/client model. Both side can send data ( id sender is defined true ) but one need listen for a connection (server) and other try connect (client).

### Configuring the SRT in the Head of project (server/client)
```dart
import 'package:srt_dart/srt_dart.dart';
/// for flutter projects, add 
import 'package:srt_flutter_libs/main.dart';

/// On the head of project
void main(){
  /// in flutter projects, use
  WidgetsFlutterBinding.ensureInitialized();
  initializeSrtFlutter();

  /// in dart projects, use
  Srt();

}
```

### Configure a Server
```dart
import 'dart:io' show InternetAddress;
final serverSocket = SrtSocket(options: SocketOptions.liveMode(sender: false)) /// Create the socket of server
serverSocket.bind(InternetAddress.loopbackIPv4, 9000); /// set the ip (127.0.0.1) and port of the server will listen
serverSocket.listen(backlog: 1); /// listen for clients
final handle = serverSocket.accept(); /// accpet one client, and get one socket to manage this connection 
handle.waitStream(onReceive : (data){
  print(data.lenght);
});
```

### Configure a Client
```dart
import 'dart:io' show InternetAddress;

final address = InternetAddress.loopbackIPv4; // the ip of server
final clientSocket = SrtSocket(options: SocketOptions.liveMode(sender: true)); /// Create the socket of Client
clientSocket.connect(address, 9000); /// try connect in ip (127.0.0.1) and port (9000) of server
final text = "when need send a text, use the menssage api"; /// the data to be send
clientSocket.sendStrem(Uint8List.fromList(text.codeUnits)); /// send the data to server
```

### On end, close the SRT.
On Flutter this step not is necessary

```dart
void doThisOnEnd(){
  Srt.cleanUp();
}
```

---

For more examples
 - see the path `example/...` 
 - A real, flutter, aplication in the [laughing-dollop repsitory](https://github.com/NoachDev/laughing-dollop)


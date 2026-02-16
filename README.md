**Welcome to the Secure Reliable Transport wrapper for Dart**

SRT is a high-level protocol for streaming data with security and integrity. Primarily made in C/C++, see the [Haivision SRT repository](https://github.com/Haivision/srt).

The current library consumes the raw code and provides a Dart-like interface with sugar on top.

## First Steps:
Built on the UDP protocol, the transport is done using a server/client model.

### In a Dart environment
If you want to use the `srt_dart` library with pure Dart, the `libsrt` package is required. Follow the SRT [Build Documentation](https://github.com/Haivision/srt/tree/master/docs#build-instructions) for more details.

In Flutter apps this step is unnecessary.

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

### Configure a Server
```dart
import 'dart:io'c show InternetAddress;

/// in the head of project
void main(){
  /// in flutter projects
  /// WidgetsFlutterBinding.ensureInitialized();

  Srt()
  ...
}

// some fictice function to create a server
void createAServer(){
  final serverSocket = SrtSocket(options: SocketOptions.liveMode(sender: false)) /// Create the socket of server
  serverSocket.bind(InternetAddress.loopbackIPv4, 9000); /// set the ip (127.0.0.1) and port of the server will listen
  serverSocket.listen(backlog: 1); /// listen for clieants
  final handle = serverSocket.accept(); /// accpet one client, and get one socket to manage this connection 
  await for (final data in handle.waitStream()){
    print(data); // the data reciveid from client
  }
}
```

### Configure a Client
```dart
import 'dart:io'c show InternetAddress;

/// in the head of project
void main(){
  /// in flutter projects
  /// WidgetsFlutterBinding.ensureInitialized();

  Srt()
  ...
}

// some fictice function to create a client
void createAClient(){
  final clientSocket = SrtSocket(options: SocketOptions.liveMode(sender: false)) /// Create the socket of Client
  clientSocket.connect(InternetAddress.loopbackIPv4, 9000); /// try connect in ip (127.0.0.1) and port (9000) of server
  final text = "when need send a text, use the menssage api"; /// the data to be sened to server
  clientSocket.sendStrem(Uint8List.fromList(text.codeUnits)) /// send the data to server
}
```

---

For more examples
 - see the path `example/...` 
 - A real, flutter, aplication in the [laughing-dollop repsitory](https://github.com/NoachDev/laughing-dollop)


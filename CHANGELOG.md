## 1.0.0

- Initial version.

### Foundation (Lifecycle & Core Wrappers)
- Expose srtStartup() and srtCleanup() in a dart frindely class - Srt
  - Constructor SrtSocket, that calls srt_create_socket()
  - `bind` → wraps srt_bind()
  - `listen` → wraps srt_listen()
  - `accept` → wraps srt_accept()
  - `connect` → wraps srt_connect()
  - `dispose` → wraps srt_close()
  - `state` → wraps srt_getsockstate() (returns enum: OPENED, LISTENING, CONNECTING, CONNECTED, CLOSING, CLOSED)
- Create Error handling:
  - `checkSrtResult` show socket propietes when passed a non-expected value
  - `SrtException` throw a srt_getlasterror_str() 
- Implement type-safe option builders:
  - `SocketOptions` class integrated with srt_setsockopt() with setters for common options (MSS, encryption, buffers, etc.)

### Data Transfer - Stream, Message & File Transfer Modes
- Extend srt_socket.dart with:
  - `sendStream` → wraps srt_send()
  - `recvStream` → wraps srt_recv/srt_sendmsg2()
  - `sendMessage` → wraps srt_sendmsg2() with SRT_MSGCTRL in a dart frindely class
    - `MessageControl` wrapper for SRT_MSGCTRL with builder pattern
  - `recvMessage` → wraps srt_recvmsg2() and return a dart friendly class
    - `SrtMessage` class (payload, timestamp, sequence, etc.)
  - `sendFile` → wraps srt_sendfile()
  - `recvFile` → wraps srt_recvfile()
  - `getStats` → wraps srt_bstats() with SocketStats return type
  - `getLocalAddress` → wraps srt_getsockname() with address/port parsing
  - `getRemoteAddress` → wraps srt_getpeername() with address/port parsing
  - `SocketStats` class with comprehensive statistics fields

### Epoll + Sugar on Top
- SrtEpoll class wrapping epoll functionality
  - `register` → wraps srt_epoll_add_usock() with EpollEventType enum
  - `unregister` → wraps srt_epoll_remove_usock()
  - `waitAsync` → wraps srt_epoll_wait() (returns list of ready events: READ, WRITE, ERROR)
  - `clear` → wraps srt_epoll_clear_usocks()
  - `dispose` → wraps srt_epoll_release()
  - `waitAsStream` → Continuous event stream
- Extend SrtSocket with:
  - `waitStream` - Continuous data of recvStream.
  - `waitMessage` - Continuous data of recvMenssage.
  - `accept` in a theared for async performece
  - `sendStrem` with a chunked mode for large data.

- Comprehensive unit tests for stream and message modes, and a documentation.

## 1.1.0

### Enhence the even-drive methods
  - creating a class `ThreadMananger` to manage isolates -> async methods
  - update the epoll to detect incoming data
    - Unifing the `waitStream` / `waitMessage` of SrtSocket in Epoll.

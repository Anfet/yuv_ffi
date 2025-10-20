import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class DataWriter {
  WriteBuffer _buffer = WriteBuffer();
  final Sink<List<int>> _sink;

  DataWriter(this._sink);

  void write() {
    _sink.add(_buffer.done().buffer.asUint8List());
    _buffer = WriteBuffer();
  }

  void writeUint8(int value) {
    _buffer.putUint8(value);
  }

  void writeUint16(int value) {
    _buffer.putUint16(value, endian: Endian.little);
  }

  void writeUint32(int value) {
    _buffer.putUint32(value, endian: Endian.little);
  }

  void writeDouble(double value) {
    _buffer.putFloat64(value, endian: Endian.little);
  }

  void writeString(String value) {
    var encoded = utf8.encode(value);
    var length = encoded.length;

    writeUint32(length);
    _buffer.putUint8List(encoded);
  }

  void writeBytes(Uint8List value) {
    writeUint32(value.length);
    _buffer.putUint8List(value);
  }
}

class DataReader with ChangeNotifier {
  WriteBuffer _writeBuffer = WriteBuffer();
  ReadBuffer? _readBuffer;
  final Stream<List<int>> _stream;
  final Completer<void> _doneCompleter = Completer();

  DataReader(this._stream) {
    _stream.listen(
      (bytes) {
        _writeBuffer.putUint8List(Uint8List.fromList(bytes));
        notifyListeners();
      },
      onDone: () {
        _readBuffer = ReadBuffer(_writeBuffer.done());
        _doneCompleter.complete();
      },
      onError: (ex, stack) => _doneCompleter.completeError(ex, stack),
      cancelOnError: true,
    );
  }

  Future<void> done() => _doneCompleter.future;

  int readUint8() {
    assert(_readBuffer != null, 'reading is not ready, use done ');
    assert(_readBuffer!.data.buffer.lengthInBytes >= 1, 'there is no sufficient bytes available to read (1)}');

    return _readBuffer!.getUint8();
  }

  int readUint16() {
    assert(_readBuffer != null, 'reading is not ready, use done ');
    assert(_readBuffer!.data.buffer.lengthInBytes >= 2, 'there is no sufficient bytes available to read (2)}');

    return _readBuffer!.getUint16(endian: Endian.little);
  }

  int readUint32() {
    assert(_readBuffer != null, 'reading is not ready, use done ');
    assert(_readBuffer!.data.buffer.lengthInBytes >= 4, 'there is no sufficient bytes available to read (4)}');

    return _readBuffer!.getUint32(endian: Endian.little);
  }

  double readDouble() {
    assert(_readBuffer != null, 'reading is not ready, use done ');
    assert(_readBuffer!.data.buffer.lengthInBytes >= 8, 'there is no sufficient bytes available to read (8)}');

    return _readBuffer!.getFloat64(endian: Endian.little);
  }

  String readString() {
    assert(_readBuffer != null, 'reading is not ready, use done ');
    assert(_readBuffer!.data.buffer.lengthInBytes >= 4, 'there is no sufficient bytes to read string length (4)}');
    var length = _readBuffer!.getUint32(endian: Endian.little);
    assert(_readBuffer!.data.buffer.lengthInBytes >= length, 'there is no sufficient bytes available to read string ($length)}');
    var bytes = _readBuffer!.getUint8List(length);
    var text = utf8.decode(bytes);
    return text;
  }

  Uint8List readBytes() {
    assert(_readBuffer != null, 'reading is not ready, use done ');
    assert(_readBuffer!.data.buffer.lengthInBytes >= 4, 'there is no sufficient bytes to read string length (4)}');
    var length = _readBuffer!.getUint32(endian: Endian.little);
    assert(_readBuffer!.data.buffer.lengthInBytes >= length, 'there is no sufficient bytes available to read string ($length)}');
    var bytes = _readBuffer!.getUint8List(length);
    return bytes;
  }
}

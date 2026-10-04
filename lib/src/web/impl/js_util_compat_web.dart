// ignore_for_file: public_member_api_docs

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Object get globalThis => globalContext;

T getProperty<T>(Object object, String property) {
  final value = _asJsObject(object).getProperty<JSAny?>(property.toJS);
  return _fromJs<T>(value);
}

void setProperty(Object object, String property, Object? value) {
  _asJsObject(object).setProperty(property.toJS, _toJs(value));
}

Object newObject() => JSObject();

T callMethod<T>(Object object, String method, List<Object?> arguments) {
  final value = _asJsObject(object).callMethodVarArgs<JSAny?>(method.toJS, arguments.map(_toJs).toList(growable: false));
  return _fromJs<T>(value);
}

Future<T> promiseToFuture<T>(Object jsPromise) async {
  final value = await (jsPromise as JSPromise<JSAny?>).toDart;
  return _fromJs<T>(value);
}

bool hasProperty(Object object, String property) {
  return _asJsObject(object).has(property);
}

T callConstructor<T>(Object constructor, List<Object?> arguments) {
  final ctorObject = _asJsObject(constructor);
  final value = (ctorObject as JSFunction).callAsConstructorVarArgs<JSObject>(arguments.map(_toJs).toList(growable: false));
  return _fromJs<T>(value);
}

Object jsify(Object? value) => value.jsify() as Object;

JSObject _asJsObject(Object object) {
  if (object.isA<JSObject>()) {
    return object as JSObject;
  }
  return JSObject.fromInteropObject(object);
}

JSAny? _toJs(Object? value) {
  if (value == null) {
    return null;
  }
  if (value.isA<JSAny>()) {
    return value as JSAny;
  }
  return value.jsify();
}

T _fromJs<T>(JSAny? value) {
  if (value == null) {
    if (null is T) {
      return null as T;
    }
    throw StateError('Expected $T from JavaScript, got null.');
  }

  if (T == Object) {
    if (value.isA<JSNumber>() || value.isA<JSBoolean>() || value.isA<JSString>()) {
      return value.dartify() as T;
    }
    return (value as dynamic) as T;
  }

  final dartValue = value.dartify();
  if (dartValue is T) {
    return dartValue;
  }
  throw StateError('Expected $T from JavaScript, got ${dartValue.runtimeType}.');
}

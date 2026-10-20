import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('Razorpay')
extension type _Razorpay._(JSObject _) implements JSObject {
  external factory _Razorpay(JSObject options);
  external void open();
}

/// Web checkout via Razorpay checkout.js (loaded in web/index.html). Returns the signed result, or null if dismissed.
Future<Map<String, String>?> openCheckout(Map c, Map<String, String> prefill) {
  final done = Completer<Map<String, String>?>();
  final opts = {
    'key': c['key_id'],
    'order_id': c['order_id'],
    'amount': c['amount'],
    'currency': c['currency'],
    'name': c['name'],
    'description': c['description'],
    'prefill': prefill,
  }.jsify() as JSObject;
  opts['handler'] = ((JSObject r) {
    final m = (r.dartify() as Map).map((k, v) => MapEntry('$k', '$v'));
    if (!done.isCompleted) done.complete(m);
  }).toJS;
  final modal = JSObject();
  modal['ondismiss'] = (() {
    if (!done.isCompleted) done.complete(null);
  }).toJS;
  opts['modal'] = modal;
  _Razorpay(opts).open();
  return done.future;
}

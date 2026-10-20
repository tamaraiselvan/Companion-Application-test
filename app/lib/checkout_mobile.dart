import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Android / iOS checkout via the Razorpay SDK. Returns the signed result, or null if cancelled/failed.
Future<Map<String, String>?> openCheckout(Map c, Map<String, String> prefill) {
  final done = Completer<Map<String, String>?>();
  final rp = Razorpay();
  rp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
    if (!done.isCompleted) {
      done.complete({
        'razorpay_order_id': r.orderId ?? '',
        'razorpay_payment_id': r.paymentId ?? '',
        'razorpay_signature': r.signature ?? '',
      });
    }
  });
  rp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
    if (!done.isCompleted) done.complete(null);
  });
  rp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {});
  rp.open({
    'key': c['key_id'],
    'order_id': c['order_id'],
    'amount': c['amount'],
    'currency': c['currency'],
    'name': c['name'],
    'description': c['description'],
    'prefill': prefill,
  });
  return done.future.whenComplete(rp.clear);
}

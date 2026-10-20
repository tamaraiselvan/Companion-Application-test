import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'checkout_mobile.dart' if (dart.library.js_interop) 'checkout_web.dart' as impl;
import 'state.dart';

/// Opens Razorpay checkout for a backend-created order and verifies the result with the backend.
/// Returns true only when the server confirmed the payment signature.
Future<bool> payAndVerify(BuildContext context, Map checkout) async {
  final u = context.read<AppState>().user ?? {};
  Map<String, String>? r;
  try {
    r = await impl.openCheckout(checkout, {'name': '${u['name'] ?? ''}', 'email': '${u['email'] ?? ''}', 'contact': '${u['phone'] ?? ''}'});
  } catch (e) {
    debugPrint('Checkout failed: $e');
  }
  if (r == null) return false;
  try {
    final v = await Api.I.post('/payments/verify/', r);
    return v['status'] == 'paid';
  } catch (_) {
    return false;
  }
}

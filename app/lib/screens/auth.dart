import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../widgets.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
      backgroundColor: C.ink,
      body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('🤝', style: TextStyle(fontSize: 56)),
        SizedBox(height: 12),
        Text('dayfello', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600)),
        SizedBox(height: 20),
        CircularProgressIndicator(color: C.coral),
      ])));
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingScreen> {
  static const slides = [
    ('🧑‍🤝‍🧑', 'Trusted human companionship', 'Verified companions for seniors, patients, children, travel, pets and events — matched by AI.'),
    ('📍', 'Live tracking, always', 'Know where your companion is with real-time tracking and ETA.'),
    ('🛡️', 'Safety first', 'Background-checked companions, in-app SOS, and 24/7 support on every booking.'),
  ];
  int i = 0;
  bool policy = false;

  @override
  Widget build(BuildContext context) {
    final last = i == slides.length;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Expanded(
              child: last
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Almost there', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: C.ink)),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        value: policy,
                        onChanged: (v) => setState(() => policy = v!),
                        title: const Text('I accept the Privacy Policy and Terms of Service.'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ])
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(slides[i].$1, style: const TextStyle(fontSize: 64)),
                      const SizedBox(height: 20),
                      Text(slides[i].$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: C.ink)),
                      const SizedBox(height: 8),
                      Text(slides[i].$3, textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
                    ]),
            ),
            Row(children: List.generate(slides.length + 1, (k) => Expanded(
                child: Container(
                    height: 5,
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                        color: k <= i ? C.coral : C.sandDark, borderRadius: BorderRadius.circular(4)))))),
            const SizedBox(height: 16),
            Row(children: [
              if (i > 0) OutlinedButton(onPressed: () => setState(() => i--), child: const Text('Back')),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      onPressed: last
                          ? (policy ? () => context.read<AppState>().finishOnboarding() : null)
                          : () => setState(() => i++),
                      child: Text(last ? 'Get started' : 'Next'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final id = TextEditingController(), pw = TextEditingController();
  bool otp = false, busy = false;

  Future<void> submit() async {
    setState(() => busy = true);
    final s = context.read<AppState>();
    await guard(context, () => otp ? s.loginOtp(id.text.trim(), pw.text.trim()) : s.login(id.text.trim(), pw.text));
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
                const Text('🤝', style: TextStyle(fontSize: 40)),
                const Text('Welcome back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: C.ink)),
                const Text('Log in to book a companion in minutes.', style: TextStyle(color: C.muted)),
                const SizedBox(height: 20),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Password')),
                    ButtonSegment(value: true, label: Text('OTP')),
                  ],
                  selected: {otp},
                  onSelectionChanged: (v) => setState(() => otp = v.first),
                ),
                const SizedBox(height: 14),
                TextField(
                    controller: id,
                    decoration: InputDecoration(labelText: otp ? 'Mobile (+91…)' : 'Mobile, email or username')),
                const SizedBox(height: 12),
                TextField(
                    controller: pw,
                    obscureText: !otp,
                    keyboardType: otp ? TextInputType.number : null,
                    decoration: InputDecoration(
                      labelText: otp ? '6-digit code' : 'Password',
                      suffixIcon: otp
                          ? TextButton(
                              onPressed: () => guard(context, () => Api.I.post('/auth/otp/request/', {'phone': id.text.trim()}),
                                  ok: 'Code sent by SMS'),
                              child: const Text('Send code'))
                          : null,
                    ),
                    onSubmitted: (_) => submit()),
                const SizedBox(height: 18),
                FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait…' : 'Continue')),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: const Text('New here? Create an account')),
              ]),
            ),
          ),
        ),
      );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterState();
}

class _RegisterState extends State<RegisterScreen> {
  final f = {for (final k in ['name', 'phone', 'email', 'address', 'emergency_contact', 'password']) k: TextEditingController()};
  static const labels = {
    'name': 'Full name', 'phone': 'Mobile number (+91…)', 'email': 'Email', 'address': 'Address',
    'emergency_contact': 'Emergency contact (name & number)', 'password': 'Password (min 8 chars)'
  };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          for (final e in f.entries) ...[
            TextField(controller: e.value, obscureText: e.key == 'password', decoration: InputDecoration(labelText: labels[e.key])),
            const SizedBox(height: 12),
          ],
          FilledButton(
              onPressed: () async {
                final ok = await guard(context,
                    () => context.read<AppState>().register({for (final e in f.entries) e.key: e.value.text.trim()}).then((_) => true));
                if (ok == true && context.mounted) Navigator.pop(context);
              },
              child: const Text('Create account')),
        ]),
      );
}

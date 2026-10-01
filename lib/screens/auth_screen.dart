import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/roam_api.dart';
import '../style_labels.dart';
import '../theme.dart';

/// Sign up / log in screen. Both call into the same [RoamApi] instance the
/// rest of the app shares, so a successful auth here is immediately visible
/// to every other screen (session token / Supabase session is held on the
/// api object itself).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, this.startInLogin = false});

  final RoamApi api;
  final bool startInLogin;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _login = widget.startInLogin;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _style = 'solo';
  var _submitting = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    if (!_login && _nameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = _login
          ? await widget.api.login(email, password)
          : await widget.api.register(
              name: _nameController.text.trim(),
              email: email,
              password: password,
              style: _style,
            );
      if (!mounted) return;
      if (result['confirmation_required'] == true) {
        setState(() {
          _notice = 'Check your email to confirm your account, then log in.';
          _login = true;
          _submitting = false;
        });
        return;
      }
      Navigator.of(context).pop(true);
    } on RoamApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: RoamColors.offwhite,
    appBar: AppBar(
      backgroundColor: RoamColors.navyTint,
      foregroundColor: Colors.white,
      title: Text(
        _login ? 'Log In' : 'Join Roam Together',
        style: GoogleFonts.breeSerif(color: Colors.white, fontSize: 18),
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ToggleButtons(
              borderRadius: BorderRadius.circular(10),
              isSelected: [!_login, _login],
              onPressed: _submitting
                  ? null
                  : (index) => setState(() {
                      _login = index == 1;
                      _error = null;
                      _notice = null;
                    }),
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Text('Sign Up')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Text('Log In')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_notice != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: RoamColors.mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_notice!, style: const TextStyle(color: RoamColors.emerald)),
            ),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: RoamColors.coral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: const TextStyle(color: RoamColors.coral)),
            ),
            const SizedBox(height: 16),
          ],
          if (!_login) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: _login ? null : 'At least 12 characters',
              border: const OutlineInputBorder(),
            ),
          ),
          if (!_login) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _style,
              decoration: const InputDecoration(labelText: 'Travel style', border: OutlineInputBorder()),
              items: [
                for (final entry in styleLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => setState(() => _style = value ?? _style),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: RoamColors.emerald,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(_login ? 'Log In' : 'Create account'),
          ),
        ],
      ),
    ),
  );
}

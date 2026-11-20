import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/widgets.dart';
import 'auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoggedIn});
  final VoidCallback onLoggedIn;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _repo = AuthRepository(createDio());
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _username = TextEditingController();
  final _country = TextEditingController(text: 'TN');
  bool _register = false;
  bool _loading = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _password, _first, _last, _username, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_register) {
        await _repo.register({
          'firstName': _first.text.trim(),
          'lastName': _last.text.trim(),
          'username': _username.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
          'country': _country.text.trim().toUpperCase(),
        });
      } else {
        await _repo.login(_email.text.trim(), _password.text);
      }
      widget.onLoggedIn();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _serverDialog() async {
    final c = TextEditingController(text: await currentBaseUrl());
    if (!mounted) return;
    String? msg;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Adresse du serveur'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'http://192.168.1.14:8080'),
            ),
            if (msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg!)),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                final ok = await pingServer(c.text.trim().replaceAll(RegExp(r'/+$'), ''));
                setS(() => msg = ok ? 'Serveur joignable ✓' : 'Serveur injoignable ✗');
              },
              child: const Text('Tester'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                await storage.write(
                    key: 'server_url', value: c.text.trim().replaceAll(RegExp(r'/+$'), ''));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? type,
    String? Function(String?)? validator,
    Widget? suffix,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          obscureText: obscure,
          keyboardType: type,
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      );

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.dns_outlined),
                    tooltip: 'Adresse du serveur',
                    onPressed: _serverDialog,
                  ),
                ),
                const FocusRing(
                  size: 130,
                  progress: 0.78,
                  c1: AppColors.accent,
                  c2: AppColors.accent2,
                  child: Text('F', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w200)),
                ),
                const SizedBox(height: 12),
                const Text('Focusely', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Chaque minute compte.', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                GlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _form,
                    child: Column(children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Connexion')),
                          ButtonSegment(value: true, label: Text('Inscription')),
                        ],
                        selected: {_register},
                        onSelectionChanged: (s) => setState(() {
                          _register = s.first;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        child: _register
                            ? Column(children: [
                                Row(children: [
                                  Expanded(child: _field(_first, 'Prénom', Icons.person_outline, validator: _required)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _field(_last, 'Nom', Icons.badge_outlined, validator: _required)),
                                ]),
                                _field(_username, 'Pseudonyme', Icons.alternate_email, validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.length < 3) return '3 caractères minimum';
                                  if (!RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(t)) return 'Lettres, chiffres, _ et . seulement';
                                  return null;
                                }),
                                _field(_country, 'Pays (2 lettres, ex : TN)', Icons.public, validator: (v) {
                                  return (v ?? '').trim().length == 2 ? null : '2 lettres';
                                }),
                              ])
                            : const SizedBox(width: double.infinity),
                      ),
                      _field(_email, 'Email', Icons.mail_outline, type: TextInputType.emailAddress, validator: (v) {
                        final t = (v ?? '').trim();
                        return (t.contains('@') && t.contains('.')) ? null : 'Email invalide';
                      }),
                      _field(
                        _password,
                        'Mot de passe',
                        Icons.lock_outline,
                        obscure: _hide,
                        validator: (v) => (v ?? '').length >= 8 ? null : '8 caractères minimum',
                        suffix: IconButton(
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.pink.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_error!, style: const TextStyle(color: AppColors.pink)),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_register ? 'Créer mon compte' : 'Se connecter',
                                  style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

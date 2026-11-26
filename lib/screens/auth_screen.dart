import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _auth = AuthService();
  bool _isSignUp = false;
  bool _busy = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _message(String value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_isSignUp) {
        final signedIn = await _auth.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
        if (!signedIn) {
          _message('Аккаунт создан. Подтверди email по ссылке из письма, затем войди.');
        }
      } else {
        await _auth.signIn(email: _email.text, password: _password.text);
      }
    } on AuthException catch (e) {
      _message(e.message, error: true);
    } catch (e) {
      _message('Не удалось выполнить запрос: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _message('Сначала введи корректный email.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.resetPassword(email);
      _message('Письмо для восстановления пароля отправлено, если аккаунт существует.');
    } on AuthException catch (e) {
      _message(e.message, error: true);
    } catch (e) {
      _message('Не удалось отправить письмо: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.movie_creation_outlined, size: 52),
                      const SizedBox(height: 12),
                      const Text('KinoKino', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      const Text('by Osirisvectory', textAlign: TextAlign.center),
                      const SizedBox(height: 28),
                      Text(_isSignUp ? 'Создать аккаунт' : 'Вход в аккаунт',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 18),
                      if (_isSignUp) ...[
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Имя', prefixIcon: Icon(Icons.person_outline)),
                          validator: (v) => _isSignUp && (v == null || v.trim().length < 2)
                            ? 'Укажи имя (минимум 2 символа)' : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                        validator: (v) => v == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())
                          ? 'Введи корректный email' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _hidePassword,
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _hidePassword = !_hidePassword),
                            icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
                          ),
                        ),
                        validator: (v) => v == null || v.length < 8 ? 'Минимум 8 символов' : null,
                      ),
                      if (!_isSignUp)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy ? null : _resetPassword,
                            child: const Text('Забыли пароль?'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isSignUp ? 'Зарегистрироваться' : 'Войти'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _isSignUp = !_isSignUp),
                        child: Text(_isSignUp ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Регистрация'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.tvMode = false});
  final bool tvMode;
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
    if (!tvMode) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _loginForm(context, tv: false),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      body: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF101B2D), Color(0xFF080B12), Color(0xFF090A0C)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 28 : constraints.maxWidth * .07,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: compact
                    ? Center(child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: _loginForm(context, tv: true),
                      ))
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 48),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Icon(Icons.movie_filter_rounded, size: 76, color: Color(0xFFFFD21F)),
                                  SizedBox(height: 22),
                                  Text('KinoKino TV', style: TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: Colors.white)),
                                  SizedBox(height: 14),
                                  Text('Фильмы и сериалы на большом экране',
                                    style: TextStyle(fontSize: 25, color: Colors.white70)),
                                  SizedBox(height: 34),
                                  Text('Управляйте приложением с помощью пульта',
                                    style: TextStyle(fontSize: 18, color: Colors.white54)),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Center(child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 620),
                              child: _loginForm(context, tv: true),
                            )),
                          ),
                        ],
                      ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _loginForm(BuildContext context, {required bool tv}) {
    final scale = tv ? 1.18 : 1.0;
    return Card(
      color: const Color(0xFF171B24),
      child: Padding(
        padding: EdgeInsets.all(tv ? 34 : 28),
        child: FocusTraversalGroup(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!tv) ...[
                  const Icon(Icons.movie_creation_outlined, size: 52),
                  const SizedBox(height: 12),
                  const Text('KinoKino', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const Text('by Osirisvectory', textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                ] else ...[
                  const Text('ВХОД В АККАУНТ', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 24),
                ],
                Text(_isSignUp ? 'Создать аккаунт' : 'Вход в аккаунт',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22 * scale)),
                const SizedBox(height: 20),
                if (_isSignUp) ...[
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Имя', prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => _isSignUp && (v == null || v.trim().length < 2)
                      ? 'Укажи имя (минимум 2 символа)' : null,
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  validator: (v) => v == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())
                    ? 'Введи корректный email' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _hidePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _busy ? null : _submit(),
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
                SizedBox(
                  height: tv ? 58 : null,
                  child: FilledButton(
                    autofocus: tv,
                    onPressed: _busy ? null : _submit,
                    child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_isSignUp ? 'Зарегистрироваться' : 'Войти',
                          style: TextStyle(fontSize: tv ? 19 : null)),
                  ),
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
    );
  }
}

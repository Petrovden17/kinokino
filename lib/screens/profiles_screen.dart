import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key, required this.service});
  final ProfileService service;
  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  String? _message;
  Future<void> _create() async {
    final name = TextEditingController();
    final password = TextEditingController();
    final pin = TextEditingController();
    bool child = false;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) =>
        AlertDialog(
          title: const Text('Новый профиль'),
          content: Form(key: formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Имя профиля'),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Минимум 2 символа' : null),
            const SizedBox(height: 10),
            TextFormField(controller: password, obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль (от 8 символов)'),
              validator: (v) => (v == null || v.length < 8) ? 'Минимум 8 символов' : null),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Детский профиль'),
              value: child,
              onChanged: (v) => setDialog(() => child = v),
            ),
            if (child) TextFormField(controller: pin, keyboardType: TextInputType.number,
              maxLength: 6, obscureText: true,
              decoration: const InputDecoration(labelText: 'Родительский PIN (4–6 цифр)'),
              validator: (v) => child && (v == null || !RegExp(r'^\d{4,6}$').hasMatch(v)) ? 'Введите 4–6 цифр' : null),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(dialogContext, 'create');
            }, child: const Text('Создать')),
          ],
        )),
    );
    if (result != 'create') return;
    try {
      final recovery = await widget.service.createProfile(
        name: name.text, password: password.text, isChild: child, pin: child ? pin.text : null);
      if (!mounted) return;
      await showDialog<void>(context: context, barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Код восстановления'),
          content: SelectableText('$recovery\n\nСохраните его в надёжном месте. Повторно показать код будет невозможно.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Я сохранил код'))],
        ));
      setState(() => _message = 'Профиль создан.');
    } catch (e) {
      setState(() => _message = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _login(UserProfile profile) async {
    final password = TextEditingController();
    final pin = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Войти: ${profile.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: password, obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль')),
          if (profile.isChild) ...[
            const SizedBox(height: 10),
            TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN')),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'recover'), child: const Text('Забыли пароль?')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'login'), child: const Text('Войти')),
        ],
      ),
    );
    if (result == 'recover') { await _recover(profile); return; }
    if (result != 'login') return;
    final passwordOk = await widget.service.authenticate(profile.id, password.text);
    final pinOk = !profile.isChild || await widget.service.authenticatePin(profile.id, pin.text);
    if (passwordOk && pinOk) {
      await widget.service.selectProfile(profile.id);
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _message = 'Неверный пароль или PIN.');
    }
  }

  Future<void> _recover(UserProfile profile) async {
    final code = TextEditingController();
    final newPassword = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Восстановление доступа'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: code, decoration: const InputDecoration(labelText: 'Код восстановления')),
        const SizedBox(height: 10),
        TextField(controller: newPassword, obscureText: true,
          decoration: const InputDecoration(labelText: 'Новый пароль (от 8 символов)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сменить пароль')),
      ],
    ));
    if (result != true) return;
    final ok = await widget.service.recoverPassword(profile.id, code.text, newPassword.text);
    setState(() => _message = ok ? 'Пароль изменён. Теперь войдите с новым паролем.' : 'Код неверен или новый пароль короче 8 символов.');
  }

  @override
  Widget build(BuildContext context) {
    final activeId = widget.service.activeProfile?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Профили')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create, icon: const Icon(Icons.add), label: const Text('Добавить')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_message != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_message!)),
          if (widget.service.profiles.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Text('Пока нет профилей. Создайте первый профиль.')),
          for (final profile in widget.service.profiles)
            Card(child: ListTile(
              leading: CircleAvatar(child: Icon(profile.isChild ? Icons.child_care : Icons.person)),
              title: Text(profile.name),
              subtitle: Text(profile.isChild ? 'Детский профиль · защищён PIN' : 'Обычный профиль'),
              trailing: activeId == profile.id
                ? const Chip(label: Text('Активен'))
                : const Icon(Icons.chevron_right),
              onTap: () => _login(profile),
            )),
          const SizedBox(height: 80),
          const Text('Пароли, PIN и коды восстановления хранятся в защищённом хранилище устройства в виде криптографических хешей. Код восстановления показывается только один раз.',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }
}

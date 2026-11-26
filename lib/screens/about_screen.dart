import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('О KinoKino')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text('KinoKino', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text(
          'Создано by Osirisvectory при помощи ChatGPT.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 24),
        Text('Благодарности и использованные технологии',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        _ServiceLine(name: 'Flutter и Dart', detail: 'Основа приложения и интерфейса'),
        _ServiceLine(name: 'The Movie Database (TMDB)', detail: 'Информация о фильмах, сериалах, постеры и каталог'),
        _ServiceLine(name: 'Watchmode', detail: 'Данные о доступности контента и видеосервисах'),
        _ServiceLine(name: 'Cloudflare Workers', detail: 'Промежуточный API для запросов к внешним каталогам'),
        _ServiceLine(name: 'Supabase', detail: 'Аккаунты, авторизация и облачная база данных'),
        _ServiceLine(name: 'Internet Archive', detail: 'Поиск отдельных архивных видео и открытых материалов'),
        _ServiceLine(name: 'GitHub и GitHub Actions', detail: 'Хранение исходного кода и автоматическая проверка сборок'),
        _ServiceLine(name: 'GitHub Releases', detail: 'Публикация версий приложения и обновлений'),
        _ServiceLine(name: 'video_player и video_player_win', detail: 'Воспроизведение видео'),
        _ServiceLine(name: 'Dio', detail: 'Сетевые запросы'),
        _ServiceLine(name: 'cached_network_image', detail: 'Загрузка и кэширование изображений'),
        _ServiceLine(name: 'SharedPreferences и SQLite', detail: 'Локальные настройки и данные библиотеки'),
        _ServiceLine(name: 'url_launcher', detail: 'Открытие внешних ссылок'),
        _ServiceLine(name: 'flutter_secure_storage, archive, crypto, uuid, path_provider', detail: 'Вспомогательные функции и работа с файлами'),
        SizedBox(height: 20),
        Text(
          'Названия сторонних сервисов и технологий приведены для указания использованных источников и инструментов. Они принадлежат их правообладателям.',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    ),
  );
}

class _ServiceLine extends StatelessWidget {
  const _ServiceLine({required this.name, required this.detail});
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(detail, style: const TextStyle(color: Colors.white70)),
      ],
    ),
  );
}

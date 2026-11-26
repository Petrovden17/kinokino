# KinoKino 1.0

Новая исходная кодовая база KinoKino на Flutter. Этот архив содержит этапы 1.0 и 1.1: адаптивная оболочка, каталог TMDB, поиск, карточка подробностей, локальное избранное и история просмотров.

## Требования

- Flutter stable (Dart 3.4+)
- Android SDK для Android
- Visual Studio с workload **Desktop development with C++** для Windows

## Запуск

1. Распакуйте архив.
2. В терминале VS Code откройте папку `KinoKino_1.0`.
3. Выполните:

```bash
flutter create . --platforms=android,windows
flutter pub get
```

4. Получите собственный ключ API на https://www.themoviedb.org/settings/api.
5. Запустите:

```bash
flutter run --dart-define=TMDB_API_KEY=ВАШ_TMDB_API_KEY
```

Без ключа приложение откроется, но сетевой каталог TMDB покажет понятную ошибку конфигурации.

## Сборка

```bash
flutter build apk --release --dart-define=TMDB_API_KEY=ВАШ_TMDB_API_KEY
flutter build windows --release --dart-define=TMDB_API_KEY=ВАШ_TMDB_API_KEY
```

Android TV пока не выделен в отдельный flavor: для полноценной публикации Android TV потребуется отдельная настройка manifest, Leanback launcher, баннеров и проверка навигации пультом.

## Структура

- `lib/core` — общие настройки и тема
- `lib/models` — модели данных
- `lib/services` — работа с внешними API
- `lib/repositories` — слой доступа к каталогу
- `lib/screens` — экраны
- `lib/widgets` — переиспользуемые компоненты
- `test` — тесты
- `.github/workflows` — CI-сборки

## Важно о контенте

TMDB предоставляет метаданные и изображения, но не полнометражные фильмы. Встроенный плеер и загрузки разрешённых источников, профили, SQLite/Drift, резервные копии, уведомления, полноценные фильтры и прочие функции из ТЗ ещё не реализованы. Архив не является готовой финальной версией приложения и не содержит APK/EXE.

Ключ TMDB не зашит в исходники. Для GitHub Actions добавьте секрет репозитория `TMDB_API_KEY`. Не публикуйте приватные ключи и пароли.

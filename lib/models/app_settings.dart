class AppSettings {
  const AppSettings({
    this.language = 'ru',
    this.notificationsEnabled = true,
    this.autoplay = false,
    this.defaultPlaybackSpeed = 1.0,
    this.adultContentAllowed = true,
    this.maxChildRating = 12,
  });
  final String language;
  final bool notificationsEnabled;
  final bool autoplay;
  final double defaultPlaybackSpeed;
  final bool adultContentAllowed;
  final int maxChildRating;

  AppSettings copyWith({
    String? language, bool? notificationsEnabled, bool? autoplay,
    double? defaultPlaybackSpeed, bool? adultContentAllowed, int? maxChildRating,
  }) => AppSettings(
    language: language ?? this.language,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    autoplay: autoplay ?? this.autoplay,
    defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
    adultContentAllowed: adultContentAllowed ?? this.adultContentAllowed,
    maxChildRating: maxChildRating ?? this.maxChildRating,
  );

  Map<String, Object> toJson() => {
    'language': language, 'notificationsEnabled': notificationsEnabled,
    'autoplay': autoplay, 'defaultPlaybackSpeed': defaultPlaybackSpeed,
    'adultContentAllowed': adultContentAllowed, 'maxChildRating': maxChildRating,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    language: json['language'] as String? ?? 'ru',
    notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    autoplay: json['autoplay'] as bool? ?? false,
    defaultPlaybackSpeed: (json['defaultPlaybackSpeed'] as num?)?.toDouble() ?? 1.0,
    adultContentAllowed: json['adultContentAllowed'] as bool? ?? true,
    maxChildRating: json['maxChildRating'] as int? ?? 12,
  );
}

class AppSettings {
  const AppSettings({
    this.language = 'ru',
    this.notificationsEnabled = true,
    this.autoplay = false,
    this.defaultPlaybackSpeed = 1.0,
    this.adultContentAllowed = true,
    this.maxChildRating = 12,
    this.autoUpdatesEnabled = true,
    this.updateIntervalHours = 24,
    this.accentColorValue = 0xFFFF765E,
    this.animationsEnabled = true,
    this.animationSpeed = 1.0,
    this.preferredAudioLanguage = 'auto',
    this.preferredVideoQuality = 'auto',
  });
  final String language;
  final bool notificationsEnabled;
  final bool autoplay;
  final double defaultPlaybackSpeed;
  final bool adultContentAllowed;
  final int maxChildRating;
  final bool autoUpdatesEnabled;
  final int updateIntervalHours;
  final int accentColorValue;
  final bool animationsEnabled;
  final double animationSpeed;
  final String preferredAudioLanguage;
  final String preferredVideoQuality;

  AppSettings copyWith({
    String? language, bool? notificationsEnabled, bool? autoplay,
    double? defaultPlaybackSpeed, bool? adultContentAllowed, int? maxChildRating,
    bool? autoUpdatesEnabled, int? updateIntervalHours, int? accentColorValue,
    bool? animationsEnabled, double? animationSpeed,
  }) => AppSettings(
    language: language ?? this.language,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    autoplay: autoplay ?? this.autoplay,
    defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
    adultContentAllowed: adultContentAllowed ?? this.adultContentAllowed,
    maxChildRating: maxChildRating ?? this.maxChildRating,
    autoUpdatesEnabled: autoUpdatesEnabled ?? this.autoUpdatesEnabled,
    updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
    accentColorValue: accentColorValue ?? this.accentColorValue,
    animationsEnabled: animationsEnabled ?? this.animationsEnabled,
    animationSpeed: animationSpeed ?? this.animationSpeed,
    preferredAudioLanguage: preferredAudioLanguage ?? this.preferredAudioLanguage,
    preferredVideoQuality: preferredVideoQuality ?? this.preferredVideoQuality,
  );

  Map<String, Object> toJson() => {
    'language': language, 'notificationsEnabled': notificationsEnabled,
    'autoplay': autoplay, 'defaultPlaybackSpeed': defaultPlaybackSpeed,
    'adultContentAllowed': adultContentAllowed, 'maxChildRating': maxChildRating,
    'autoUpdatesEnabled': autoUpdatesEnabled,
    'updateIntervalHours': updateIntervalHours,
    'accentColorValue': accentColorValue,
    'animationsEnabled': animationsEnabled,
    'animationSpeed': animationSpeed,
    'preferredAudioLanguage': preferredAudioLanguage,
    'preferredVideoQuality': preferredVideoQuality,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    language: json['language'] as String? ?? 'ru',
    notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    autoplay: json['autoplay'] as bool? ?? false,
    defaultPlaybackSpeed: (json['defaultPlaybackSpeed'] as num?)?.toDouble() ?? 1.0,
    adultContentAllowed: json['adultContentAllowed'] as bool? ?? true,
    maxChildRating: json['maxChildRating'] as int? ?? 12,
    autoUpdatesEnabled: json['autoUpdatesEnabled'] as bool? ?? true,
    updateIntervalHours: json['updateIntervalHours'] as int? ?? 24,
    accentColorValue: json['accentColorValue'] as int? ?? 0xFFFF765E,
    animationsEnabled: json['animationsEnabled'] as bool? ?? true,
    animationSpeed: (json['animationSpeed'] as num?)?.toDouble() ?? 1.0,
    preferredAudioLanguage: json['preferredAudioLanguage'] as String? ?? 'auto',
    preferredVideoQuality: json['preferredVideoQuality'] as String? ?? 'auto',
  );
}

import '../models/user_profile.dart';
import '../models/app_settings.dart';

class ParentalControlService {
  // TMDB ratings are country-specific. Until a country certification is fetched,
  // unknown ratings are treated conservatively for child profiles.
  bool canShow({
    required UserProfile? profile,
    required int? ageRating,
    required AppSettings settings,
  }) {
    if (profile == null || !profile.isChild) return settings.adultContentAllowed;
    if (ageRating == null) return false;
    return ageRating <= settings.maxChildRating;
  }
}

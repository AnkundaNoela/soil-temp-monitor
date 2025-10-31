// lib/config/api_keys.dart

class ApiKeys {
  // ----------------- GEMINI API KEY -----------------
  static const String geminiApiKey = 'AIzaSyBWgLBXCBbL1s2GkF4c3gFiO3HmlsRJT44';

  // ----------------- GOOGLE SEARCH API KEYS -----------------
  static const String googleSearchApiKey =
      'AIzaSyDoQE-Rw3U6fQxyKMpJoWE1Z48sPbpJ2MA';
  static const String googleSearchEngineId = '410664f0c4b3d4e0f';

  // ===================================================================
  //                      THE CORRECTED LOGIC IS HERE
  // ===================================================================
  /// Check if the core Gemini API key is configured.
  /// This now correctly checks against a generic placeholder, NOT your actual key.
  static bool get isConfigured =>
      geminiApiKey !=
          'YOUR_GEMINI_API_KEY_PLACEHOLDER' && // This line is now fixed
      geminiApiKey.isNotEmpty;
}

// ===================================================================
// SECURITY NOTE:
// ===================================================================
// Please ensure this file is in your .gitignore to keep your keys private.
// Add this line to your .gitignore file:
// /lib/config/api_keys.dart
// ===================================================================

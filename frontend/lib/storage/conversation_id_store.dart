import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ConversationIdStore {
  Future<String?> read();
  Future<void> write(String id);
}

class PreferencesConversationIdStore implements ConversationIdStore {
  PreferencesConversationIdStore({
    required Uri baseUrl,
    SharedPreferencesAsync? preferences,
  }) : _key = 'conversationId:$baseUrl',
       _preferences = preferences ?? SharedPreferencesAsync();

  final String _key;
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String id) => _preferences.setString(_key, id);
}

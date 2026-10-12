import '../models/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ConversationIdStore {
  Future<String?> read({WorldDomain domain = WorldDomain.objects});
  Future<void> write(String id, {WorldDomain domain = WorldDomain.objects});
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
  Future<String?> read({WorldDomain domain = WorldDomain.objects}) =>
      _preferences.getString(
        domain == WorldDomain.objects ? _key : '$_key:${domain.name}',
      );

  @override
  Future<void> write(String id, {WorldDomain domain = WorldDomain.objects}) =>
      _preferences.setString(
        domain == WorldDomain.objects ? _key : '$_key:${domain.name}',
        id,
      );
}

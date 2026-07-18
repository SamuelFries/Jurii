import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/profile_avatar_storage.dart';

void main() {
  const storage = ProfileAvatarStorage();
  const userId = '91000000-0000-0000-0000-000000000001';

  test('extrai somente caminho de avatar pertencente ao usuário', () {
    expect(
      storage.ownedPathFromPublicUrl(
        'https://project.supabase.co/storage/v1/object/public/'
        'profile-avatars/$userId/avatar.png?version=1',
        userId: userId,
      ),
      '$userId/avatar.png',
    );
  });

  test(
    'não oferece para remoção caminho de outro usuário ou host genérico',
    () {
      expect(
        storage.ownedPathFromPublicUrl(
          'https://project.supabase.co/storage/v1/object/public/'
          'profile-avatars/92000000-0000-0000-0000-000000000002/avatar.png',
          userId: userId,
        ),
        isNull,
      );
      expect(
        storage.ownedPathFromPublicUrl(
          'https://example.com/avatar.png',
          userId: userId,
        ),
        isNull,
      );
    },
  );
}

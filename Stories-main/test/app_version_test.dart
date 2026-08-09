import 'package:audiobook_app/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion.parse', () {
    test('parses pubspec style', () {
      final v = AppVersion.parse('1.0.0+12');
      expect(v?.build, 12);
    });

    test('parses release tag style', () {
      final v = AppVersion.parse('v1.0.0-12');
      expect(v?.build, 12);
    });
  });

  group('AppVersion.isNewerThan', () {
    test('build 12 is newer than build 9', () {
      final nine = AppVersion.parse('1.0.0+9')!;
      final twelve = AppVersion.parse('1.0.0+12')!;
      expect(twelve.isNewerThan(nine), isTrue);
      expect(nine.isNewerThan(twelve), isFalse);
    });

    test('build 8 is not newer than build 10', () {
      final eight = AppVersion.parse('v1.0.0-8')!;
      final ten = AppVersion.parse('v1.0.0-10')!;
      expect(eight.isNewerThan(ten), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:paird/core/auth/validators.dart';

void main() {
  test('identifier accepts emails and international phone numbers', () {
    expect(validateIdentifier('asha@example.com'), isNull);
    expect(validateIdentifier('+91 98765-43210'), isNull);
    expect(validateIdentifier('0091 9876543210'), isNull);
    expect(validateIdentifier(''), isNotNull);
    expect(validateIdentifier('asha@'), isNotNull);
    expect(validateIdentifier('9876543210'), isNotNull, reason: 'country code is required');
  });

  test('new password rules mirror the server minimums', () {
    expect(validateNewPassword('short'), isNotNull);
    expect(validateNewPassword('12345678'), isNotNull);
    expect(validateNewPassword('long-enough-1'), isNull);
  });
}

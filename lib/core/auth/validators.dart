/// Client-side checks mirroring backend/accounts/identifiers.py. The server
/// remains the source of truth; these only give faster feedback.
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _phoneStrip = RegExp(r'[\s\-().]');
final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

String? validateIdentifier(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Please enter your email or phone';
  if (v.contains('@')) {
    return _email.hasMatch(v) ? null : 'Enter a valid email address';
  }
  var phone = v.replaceAll(_phoneStrip, '');
  if (phone.startsWith('00')) phone = '+${phone.substring(2)}';
  if (!_e164.hasMatch(phone)) {
    return 'Enter a phone number with country code, e.g. +919876543210';
  }
  return null;
}

/// Django's default validators require at least 8 characters, reject common
/// and all-numeric passwords. Length is checked here; the rest server-side.
String? validateNewPassword(String? value) {
  final v = value ?? '';
  if (v.length < 8) return 'Password must be at least 8 characters';
  if (RegExp(r'^\d+$').hasMatch(v)) return "Password can't be entirely numeric";
  return null;
}

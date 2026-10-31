import 'config.dart';

/// Result of decoding a scanned QR code / pasted invitation text.
class InvitePayload {
  const InvitePayload({required this.code, this.server});

  final String code;
  final String? server;

  bool get isComplete => code.isNotEmpty;
}

/// Accepts three shapes:
///  * `tileremnant://join?server=https://host&code=ABCD123456` (our QR)
///  * `https://host/join?code=ABCD123456` (printed link)
///  * a bare code `ABCD123456`
InvitePayload? parseInvitePayload(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return null;

  if (text.toLowerCase().startsWith('${AppConfig.inviteScheme}://')) {
    final Uri? uri = Uri.tryParse(text);
    final String? code = uri?.queryParameters['code'];
    if (uri == null || code == null || code.trim().isEmpty) return null;
    return InvitePayload(code: code.trim().toUpperCase(), server: uri.queryParameters['server']);
  }

  final Uri? uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    final String? code = uri.queryParameters['code'];
    if (code != null && code.trim().isNotEmpty) {
      final String server = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      return InvitePayload(code: code.trim().toUpperCase(), server: server);
    }
    return null;
  }

  if (RegExp(r'^[A-Za-z0-9]{6,20}$').hasMatch(text)) {
    return InvitePayload(code: text.toUpperCase());
  }
  return null;
}

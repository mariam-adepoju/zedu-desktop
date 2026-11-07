/// A top-level message in a channel, as returned by
/// `GET /threads/channels/{channel_id}`.
class ChannelMessage {
  final String? id;
  final String senderName;
  final String? avatarUrl;
  final String text;
  final DateTime? createdAt;
  final String? status;

  /// Files, images and voice notes sent with the message, as the server
  /// returns them (`file_name`, `file_link`, `file_type`).
  final List<Map<String, dynamic>> media;

  const ChannelMessage({
    this.id,
    required this.senderName,
    required this.text,
    this.avatarUrl,
    this.createdAt,
    this.status,
    this.media = const [],
  });

  factory ChannelMessage.fromJson(Map<String, dynamic> json) {
    String? nonEmpty(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return ChannelMessage(
      id: json['id']?.toString(),
      senderName:
          nonEmpty(json['full_name']) ??
          nonEmpty(json['sender_name']) ??
          nonEmpty(json['username']) ??
          'Unknown',
      avatarUrl:
          nonEmpty(json['avatar_url']) ?? nonEmpty(json['default_avatar_url']),
      // Messages sent from the web app arrive as HTML (`<p>hi</p>`).
      text: _decodeHtmlEntities(
        (json['message']?.toString() ?? '')
            .replaceAll(
              RegExp(r'</(p|div|li)>\s*<(p|div|li|ul|ol)\b[^>]*>|<br\s*/?>'),
              '\n',
            )
            .replaceAll(RegExp(r'<[^>]*>'), ''),
      ).trim(),
      createdAt: DateTime.tryParse(
        json['created_at']?.toString() ?? '',
      )?.toLocal(),
      status: json['status']?.toString(),
      media: (json['media'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
    );
  }

  /// Decodes in a single pass, so `&amp;lt;` stays the literal text `&lt;`.
  static String _decodeHtmlEntities(String text) {
    const named = {
      'nbsp': ' ',
      'amp': '&',
      'lt': '<',
      'gt': '>',
      'quot': '"',
      'apos': "'",
    };

    return text.replaceAllMapped(
      RegExp(r'&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|(nbsp|amp|lt|gt|quot|apos));'),
      (match) {
        final name = match[3];
        if (name != null) return named[name]!;

        final code = match[1] != null
            ? int.tryParse(match[1]!)
            : int.tryParse(match[2]!, radix: 16);
        final isCharacter =
            code != null &&
            code > 0 &&
            code <= 0x10FFFF &&
            (code < 0xD800 || code > 0xDFFF);
        return isCharacter ? String.fromCharCode(code) : match[0]!;
      },
    );
  }
}

import '../../../../helpers/helpers.dart';
import 'package:zedu/features/features.dart';

void main() {
  test('ChannelMessage.fromJson maps a thread', () {
    final message = ChannelMessage.fromJson({
      'thread_id': 't-1',
      'full_name': 'Ada Lovelace',
      'avatar_url': 'https://cdn.zedu.chat/a.png',
      'message': 'hello',
      'created_at': '2026-10-21T05:14:46Z',
    });

    expect(message.senderName, 'Ada Lovelace');
    expect(message.avatarUrl, 'https://cdn.zedu.chat/a.png');
    expect(message.createdAt, DateTime.utc(2026, 10, 21, 5, 14, 46).toLocal());
  });

  test('ChannelMessage.fromJson keeps media attachments', () {
    final message = ChannelMessage.fromJson({
      'message': '',
      'media': [
        {
          'file_name': 'photo.png',
          'file_link': 'https://cdn.zedu.chat/photo.png',
          'file_type': 'png',
        },
        {
          'file_name': 'notes.pdf',
          'file_link': 'https://cdn.zedu.chat/notes.pdf',
          'file_type': 'pdf',
        },
      ],
    });

    expect(message.media, hasLength(2));
    expect(message.media.first['file_name'], 'photo.png');
    expect(message.media.last['file_type'], 'pdf');
  });

  test('ChannelMessage.fromJson defaults media to empty', () {
    expect(ChannelMessage.fromJson({'message': 'hi'}).media, isEmpty);
  });

  test('ChannelMessage.fromJson falls back and strips HTML', () {
    final message = ChannelMessage.fromJson({
      'full_name': ' ',
      'username': 'gold_salam',
      'default_avatar_url': 'https://cdn.zedu.chat/default.png',
      'message':
          '<p>Hi &amp; welcome</p><div>Line&nbsp;two</div><ul><li>a</li><li>b</li></ul>',
    });

    expect(message.senderName, 'gold_salam');
    expect(message.avatarUrl, 'https://cdn.zedu.chat/default.png');
    expect(message.text, 'Hi & welcome\nLine two\na\nb');
  });

  group('ChannelMessage.fromJson decodes HTML entities', () {
    String textOf(String html) =>
        ChannelMessage.fromJson({'message': html}).text;

    test('shows the characters the web editor escapes', () {
      expect(textOf('<p>if a &lt; b and b &gt; c</p>'), 'if a < b and b > c');
      expect(textOf('<p>I &lt;3 this</p>'), 'I <3 this');
      expect(
        textOf('<p>&quot;quoted&quot; &apos;text&apos;</p>'),
        '"quoted" \'text\'',
      );
    });

    test('decodes numeric entities', () {
      expect(textOf('it&#39;s &#x27;ok&#X27; &#128512;'), "it's 'ok' 😀");
    });

    test('decodes once, so an escaped entity stays as typed', () {
      expect(textOf('<p>type &amp;lt; for &lt;</p>'), 'type &lt; for <');
    });

    test('leaves anything that is not a valid entity alone', () {
      expect(
        textOf('AT&T &bogus; &#xFFFFFFF; &#xD800; &lt'),
        'AT&T &bogus; &#xFFFFFFF; &#xD800; &lt',
      );
    });
  });
}

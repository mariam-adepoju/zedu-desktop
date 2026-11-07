import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

class _Org extends Notifier<String> {
  @override
  String build() => 'org-a';

  void select(String orgId) => state = orgId;
}

final _orgProvider = NotifierProvider<_Org, String>(_Org.new);

/// Returns a full page at once, except the pages listed in [held], which wait
/// until the test completes them.
class _FakeDmRepository implements DmRepository {
  final held = <String, Completer<List<DmConversation>>>{};
  final requested = <String>[];

  void hold(String orgId, int page) =>
      held['$orgId/$page'] = Completer<List<DmConversation>>();

  @override
  Future<List<DmConversation>> getConversations({
    required String orgId,
    int page = 1,
    bool recentDm = false,
    String? search,
  }) {
    requested.add('$orgId/$page');
    final completer = held['$orgId/$page'];
    if (completer != null) return completer.future;
    return Future.value(_fullPage(orgId, page));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DmConversation _conversation(String id) => DmConversation(
  channelId: id,
  username: id,
  participantId: id,
  previewMessage: '',
  unreadCount: 0,
);

List<DmConversation> _fullPage(String orgId, int page) => [
  for (var i = 0; i < DmRepository.pageSize; i++)
    _conversation('$orgId-p$page-$i'),
];

void main() {
  _noFakeDmTests();

  late _FakeDmRepository repository;
  late ProviderContainer container;

  List<String> listedIds() => container
      .read(dmListProvider)
      .requireValue
      .map((c) => c.channelId)
      .toList();

  setUp(() async {
    repository = _FakeDmRepository();
    container = ProviderContainer(
      overrides: [
        dmRepositoryProvider.overrideWithValue(repository),
        currentOrgIdProvider.overrideWith((ref) => ref.watch(_orgProvider)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(dmListProvider, (_, _) {});
    await container.read(dmListProvider.future);
  });

  test('loadMore appends the next page', () async {
    await container.read(dmListProvider.notifier).loadMore();

    expect(
      listedIds(),
      [
        ..._fullPage('org-a', 1),
        ..._fullPage('org-a', 2),
      ].map((c) => c.channelId),
    );
  });

  test('two overlapping loadMore calls append the page once', () async {
    repository.hold('org-a', 2);
    final notifier = container.read(dmListProvider.notifier);

    final first = notifier.loadMore();
    final second = notifier.loadMore();
    repository.held['org-a/2']!.complete(_fullPage('org-a', 2));
    await Future.wait([first, second]);

    expect(repository.requested.where((key) => key == 'org-a/2').length, 1);
    final ids = listedIds();
    expect(ids.toSet().length, ids.length);
    expect(
      ids,
      [
        ..._fullPage('org-a', 1),
        ..._fullPage('org-a', 2),
      ].map((c) => c.channelId),
    );
  });

  test(
    'a page from the previous workspace is dropped after a switch',
    () async {
      repository.hold('org-a', 2);
      final notifier = container.read(dmListProvider.notifier);
      final pending = notifier.loadMore();

      container.read(_orgProvider.notifier).select('org-b');
      await container.read(dmListProvider.future);

      // A short page, which would also mark the new list as having no more.
      repository.held['org-a/2']!.complete([_conversation('late-from-a')]);
      await pending;

      expect(listedIds(), _fullPage('org-b', 1).map((c) => c.channelId));
      expect(container.read(dmListProvider.notifier).hasMore, isTrue);
    },
  );

  test('a page from before a refresh is dropped', () async {
    repository.hold('org-a', 2);
    final notifier = container.read(dmListProvider.notifier);
    final pending = notifier.loadMore();

    await notifier.refresh();
    repository.held['org-a/2']!.complete([_conversation('late-page')]);
    await pending;

    expect(listedIds(), _fullPage('org-a', 1).map((c) => c.channelId));
    expect(notifier.hasMore, isTrue);
  });
}

/// Returns the same conversations for every page.
class _ListDmRepository implements DmRepository {
  _ListDmRepository(this.conversations);

  final List<DmConversation> conversations;

  @override
  Future<List<DmConversation>> getConversations({
    required String orgId,
    int page = 1,
    bool recentDm = false,
    String? search,
  }) async => conversations;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _noFakeDmTests() {
  group('the list holds only what the API sent', () {
    ProviderContainer containerFor(List<DmConversation> conversations) {
      final container = ProviderContainer(
        overrides: [
          currentOrgIdProvider.overrideWithValue('org-1'),
          dmRepositoryProvider.overrideWithValue(
            _ListDmRepository(conversations),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('returns an empty list when the organisation has no DMs', () async {
      final container = containerFor(const []);

      final conversations = await container.read(dmListProvider.future);

      expect(conversations, isEmpty);
      expect(container.read(dmListProvider.notifier).hasMore, isFalse);
    });

    test('stays empty after a refresh that returns no DMs', () async {
      final container = containerFor(const []);
      await container.read(dmListProvider.future);

      await container.read(dmListProvider.notifier).refresh();

      expect(container.read(dmListProvider).value, isEmpty);
    });

    test('returns only the conversations the API sent', () async {
      final real = DmConversation(
        channelId: 'channel-1',
        username: 'Ada',
        participantId: 'user-1',
        previewMessage: 'Hi',
        unreadCount: 0,
      );
      final container = containerFor([real]);

      final conversations = await container.read(dmListProvider.future);

      expect(conversations, [real]);
    });
  });
}

import 'dart:async';

import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

final currentOrgIdProvider = Provider<String>((ref) {
  final workspace = ref.watch(workspaceProvider).selectedWorkspace;
  return workspace?.id ?? '';
});

final dmListProvider =
    AsyncNotifierProvider<DmListNotifier, List<DmConversation>>(() {
      return DmListNotifier();
    });

class SelectedDmNotifier extends Notifier<DmConversation?> {
  @override
  DmConversation? build() => null;

  void select(DmConversation? conversation) {
    state = conversation;
  }
}

final selectedDmProvider =
    NotifierProvider<SelectedDmNotifier, DmConversation?>(
      SelectedDmNotifier.new,
    );

class DmConversationActions {
  final Set<String> pinnedIds;
  final Set<String> deletedIds;

  const DmConversationActions({
    this.pinnedIds = const {},
    this.deletedIds = const {},
  });

  DmConversationActions copyWith({
    Set<String>? pinnedIds,
    Set<String>? deletedIds,
  }) => DmConversationActions(
    pinnedIds: pinnedIds ?? this.pinnedIds,
    deletedIds: deletedIds ?? this.deletedIds,
  );
}

class DmConversationActionsNotifier extends Notifier<DmConversationActions> {
  /// Where this user's pins are remembered (null while signed out).
  String? _pinnedKey;

  /// Unpinned while the saved pins were still loading, so the restore must
  /// not bring them back.
  final Set<String> _unpinnedWhileRestoring = {};

  @override
  DmConversationActions build() {
    // Rebuilt for each signed-in user, so one account never sees another's pins.
    final userId = dmPreferencesUserId(ref);
    _pinnedKey = userId == null || userId.isEmpty
        ? null
        : DmPreferencesStore.pinnedKey(userId);
    final key = _pinnedKey;
    _unpinnedWhileRestoring.clear();
    if (key != null) _restorePinned(key);
    return const DmConversationActions();
  }

  Future<void> _restorePinned(String key) async {
    final saved = await ref.read(dmPreferencesStoreProvider).read(key);
    if (!ref.mounted || _pinnedKey != key) return;
    final unpinned = Set<String>.of(_unpinnedWhileRestoring);
    _unpinnedWhileRestoring.clear();
    if (saved.isEmpty) return;
    // Keep anything pinned while the saved list was loading, and leave out
    // anything unpinned meanwhile: the latest action wins.
    state = state.copyWith(
      pinnedIds: {...saved.difference(unpinned), ...state.pinnedIds},
    );
  }

  void togglePinned(String channelId) {
    final ids = Set<String>.from(state.pinnedIds);
    if (ids.remove(channelId)) {
      _unpinnedWhileRestoring.add(channelId);
    } else {
      ids.add(channelId);
      _unpinnedWhileRestoring.remove(channelId);
    }
    state = state.copyWith(pinnedIds: ids);
    final key = _pinnedKey;
    if (key != null) {
      unawaited(ref.read(dmPreferencesStoreProvider).write(key, ids));
    }
  }

  /// Deletes the conversation on the server, then hides it from the list
  /// until the next refresh drops it and discards its draft. Closes it only
  /// if it's still the open DM. Returns false if the request failed.
  Future<bool> delete(String channelId) async {
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId.isEmpty) return false;
    try {
      await ref
          .read(dmRepositoryProvider)
          .deleteConversation(orgId: orgId, channelId: channelId);
    } catch (_) {
      return false;
    }
    state = state.copyWith(deletedIds: {...state.deletedIds, channelId});
    ref.read(dmDraftStoreProvider).clear(channelId);
    if (ref.read(selectedDmProvider)?.channelId == channelId) {
      ref.read(selectedDmProvider.notifier).select(null);
    }
    return true;
  }
}

final dmConversationActionsProvider =
    NotifierProvider<DmConversationActionsNotifier, DmConversationActions>(
      DmConversationActionsNotifier.new,
    );

class DmListNotifier extends AsyncNotifier<List<DmConversation>> {
  int _currentPage = 1;
  bool _hasMore = true;

  /// Changes on every reload, so a page still in flight from before can be
  /// dropped.
  int _listVersion = 0;

  /// The list version of the "load more" call in flight, so a second scroll
  /// does not fetch and append the same page again.
  int? _loadingMoreVersion;

  bool get hasMore => _hasMore;

  /// The last "load more" failed (offline, expired session). The DMs already
  /// loaded stay, and the sidebar offers a retry, which asks for the same
  /// page again.
  bool get loadMoreFailed => _loadMoreFailed;
  bool _loadMoreFailed = false;

  @override
  Future<List<DmConversation>> build() async {
    final orgId = ref.watch(currentOrgIdProvider);
    _listVersion++;
    _loadingMoreVersion = null;
    _loadMoreFailed = false;
    if (orgId.isEmpty) return const [];

    _currentPage = 1;
    _hasMore = true;
    return _fetchPage(orgId, 1);
  }

  Future<List<DmConversation>> _fetchPage(String orgId, int page) async {
    final repository = ref.read(dmRepositoryProvider);
    final version = _listVersion;
    final results = await repository.getConversations(orgId: orgId, page: page);
    if (version == _listVersion && results.length < DmRepository.pageSize) {
      _hasMore = false;
    }
    return results;
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    // A scroll can end several times before the first page arrives. Both calls
    // would fetch the same page and append it, showing every row twice.
    if (_loadingMoreVersion == _listVersion) return;
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId.isEmpty) return;

    final current = state.value ?? [];
    final version = _listVersion;
    _loadingMoreVersion = version;
    // Only count the page once it has loaded, so a failed load is asked for
    // again on the next scroll instead of being skipped.
    final page = _currentPage + 1;
    try {
      final next = await _fetchPage(orgId, page);
      if (version != _listVersion) return;
      _currentPage = page;
      _loadMoreFailed = false;
      // A conversation can arrive between two page requests, shifting the
      // offset and returning one already listed. Keep the list unique too.
      final knownKeys = current.map((c) => c.conversationKey).toSet();
      state = AsyncValue.data([
        ...current,
        ...next.where((c) => knownKeys.add(c.conversationKey)),
      ]);
    } catch (error) {
      if (version != _listVersion) return;
      AppLogger.w('Could not load DM page $page - $error', tag: 'DmList');
      _loadMoreFailed = true;
      // A new list, so the sidebar rebuilds and shows the retry.
      state = AsyncValue.data([...current]);
    } finally {
      if (_loadingMoreVersion == version) _loadingMoreVersion = null;
    }
  }

  Future<void> refresh() async {
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId.isEmpty) return;

    _listVersion++;
    _loadingMoreVersion = null;
    _loadMoreFailed = false;
    _currentPage = 1;
    _hasMore = true;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchPage(orgId, 1));
  }
}

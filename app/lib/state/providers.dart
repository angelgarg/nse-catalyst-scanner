import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/api.dart';
import '../data/models.dart';

/// Overridden in main() once SharedPreferences has loaded.
final prefsProvider =
    Provider<SharedPreferences>((_) => throw UnimplementedError());

final apiProvider = Provider<Api>((ref) => Api(ref.watch(prefsProvider)));

final metaProvider =
    FutureProvider<DataMeta>((ref) => ref.watch(apiProvider).meta());
final configProvider =
    FutureProvider<RemoteConfig>((ref) => ref.watch(apiProvider).config());
final summaryProvider = FutureProvider<List<StockSummary>>(
    (ref) => ref.watch(apiProvider).summary());
final eventsProvider =
    FutureProvider<List<SpikeEvent>>((ref) => ref.watch(apiProvider).events());
final universeProvider = FutureProvider<List<UniverseEntry>>(
    (ref) => ref.watch(apiProvider).universe());
final detailProvider = FutureProvider.autoDispose.family<StockDetail, String>(
    (ref, ticker) => ref.watch(apiProvider).detail(ticker));

/// Summary rows keyed by ticker, for O(1) lookups from the watchlist.
final summaryByTickerProvider = Provider<Map<String, StockSummary>>((ref) {
  final rows = ref.watch(summaryProvider).valueOrNull ?? const [];
  return {for (final r in rows) r.ticker: r};
});

RemoteConfig currentConfig(Ref ref) =>
    ref.watch(configProvider).valueOrNull ?? const RemoteConfig();

// ------------------------------------------------------------------ entitlement

class ProNotifier extends Notifier<bool> {
  static const _key = 'pro_active';

  @override
  bool build() => ref.watch(prefsProvider).getBool(_key) ?? false;

  Future<void> set(bool active) async {
    state = active;
    await ref.read(prefsProvider).setBool(_key, active);
  }
}

final proProvider = NotifierProvider<ProNotifier, bool>(ProNotifier.new);

// ------------------------------------------------------------------ watchlist

enum AddResult { added, already, limit }

class WatchlistNotifier extends Notifier<List<String>> {
  static const _key = 'watchlist';

  @override
  List<String> build() =>
      ref.watch(prefsProvider).getStringList(_key) ??
      List.of(kDefaultWatchlist);

  int get limit =>
      ref.read(proProvider) ? 1 << 30 : currentConfig(ref).freeWatchlistLimit;

  Future<AddResult> add(String ticker) async {
    if (state.contains(ticker)) return AddResult.already;
    if (state.length >= limit) return AddResult.limit;
    state = [...state, ticker];
    await ref.read(prefsProvider).setStringList(_key, state);
    return AddResult.added;
  }

  Future<void> remove(String ticker) async {
    state = state.where((t) => t != ticker).toList();
    await ref.read(prefsProvider).setStringList(_key, state);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = List.of(state);
    if (newIndex > oldIndex) newIndex -= 1;
    list.insert(newIndex, list.removeAt(oldIndex));
    state = list;
    await ref.read(prefsProvider).setStringList(_key, state);
  }
}

final watchlistProvider =
    NotifierProvider<WatchlistNotifier, List<String>>(WatchlistNotifier.new);

// ------------------------------------------------------------------ misc prefs

class BoolPref extends FamilyNotifier<bool, String> {
  @override
  bool build(String arg) => ref.watch(prefsProvider).getBool(arg) ?? false;

  Future<void> set(bool v) async {
    state = v;
    await ref.read(prefsProvider).setBool(arg, v);
  }
}

final boolPrefProvider =
    NotifierProvider.family<BoolPref, bool, String>(BoolPref.new);

const kOnboardedKey = 'onboarded_v1';

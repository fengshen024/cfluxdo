import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/utils/platform_utils.dart';
import 'package:fluxdo/utils/relative_time_clock.dart';
import 'package:fluxdo/widgets/bookmark/bookmarks_list_content.dart';
import 'package:fluxdo/widgets/topic/topic_card_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

Topic _topic({required int id, required String title, String? bookmarkName}) {
  return Topic(
    id: id,
    title: title,
    slug: 'topic-$id',
    postsCount: 1,
    replyCount: 0,
    views: 0,
    likeCount: 0,
    categoryId: '1',
    bookmarkName: bookmarkName,
  );
}

/// 自绘卡的标题画进 canvas，没有 `Text` widget —— 按卡片 key 找。
/// 这里 `_topic` 不带 bookmarkId，key 形如 `topic:<id>`。
Finder _findCard(int id) => find.byKey(ValueKey('topic:$id'));

/// 各用例里标题 → id 的映射（不同用例 id 含义不同，按用例里出现过的组合
/// 逐条登记；同标题复用同一 id，不存在歧义）。
const Map<String, int> _titleToId = {
  'Alpha': 1,
  'Beta': 2,
  'Gamma': 3,
  'No Name 1': 2,
  'No Name 2': 3,
};

Finder _findCardByTitle(String title) => _findCard(_titleToId[title]!);

/// 每个用例结束都要清掉全局分钟心跳。
///
/// `tearDown` 跑在框架的 `_verifyInvariants`（检查残留 Timer）之后，来不及，
/// 所以必须在用例体末尾调。心跳是进程级单例，自绘卡首次排版时挂上且永不解除。
void _stopMinuteClock() {
  TopicCardLayout.debugResetClockHook();
  RelativeTimeClock.instance.debugStop();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('汇总条只统计非空名称并按数量降序展示', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: _BookmarksListTestHost(
          topics: [
            _BookmarkSeed(id: 1, title: 'Alpha', bookmarkName: 'codex'),
            _BookmarkSeed(id: 2, title: 'Beta', bookmarkName: 'beta'),
            _BookmarkSeed(id: 3, title: 'Gamma', bookmarkName: 'codex'),
            _BookmarkSeed(id: 4, title: 'No Name', bookmarkName: '   '),
          ],
        ),
      ),
    );

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('codex (2)'), findsOneWidget);
    expect(find.text('beta (1)'), findsOneWidget);
    expect(find.text('未设置 (1)'), findsOneWidget);

    _stopMinuteClock();
  });

  testWidgets('切换汇总项后只显示对应名称书签，切回全部恢复完整列表', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: _BookmarksListTestHost(
          topics: [
            _BookmarkSeed(id: 1, title: 'Alpha', bookmarkName: 'codex'),
            _BookmarkSeed(id: 2, title: 'Beta', bookmarkName: 'beta'),
            _BookmarkSeed(id: 3, title: 'Gamma', bookmarkName: 'codex'),
          ],
        ),
      ),
    );

    await tester.tap(find.text('codex (2)'));
    await tester.pumpAndSettle();

    expect(_findCardByTitle('Alpha'), findsOneWidget);
    expect(_findCardByTitle('Gamma'), findsOneWidget);
    expect(_findCardByTitle('Beta'), findsNothing);

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(_findCardByTitle('Alpha'), findsOneWidget);
    expect(_findCardByTitle('Beta'), findsOneWidget);
    expect(_findCardByTitle('Gamma'), findsOneWidget);

    _stopMinuteClock();
  });

  testWidgets('点击未设置后只显示未命名书签', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: _BookmarksListTestHost(
          topics: const [
            _BookmarkSeed(id: 1, title: 'Alpha', bookmarkName: 'codex'),
            _BookmarkSeed(id: 2, title: 'No Name 1', bookmarkName: '   '),
            _BookmarkSeed(id: 3, title: 'No Name 2'),
          ],
        ),
      ),
    );

    await tester.tap(find.text('未设置 (2)'));
    await tester.pumpAndSettle();

    expect(_findCardByTitle('No Name 1'), findsOneWidget);
    expect(_findCardByTitle('No Name 2'), findsOneWidget);
    expect(_findCardByTitle('Alpha'), findsNothing);

    _stopMinuteClock();
  });

  testWidgets('隐藏汇总条再恢复后保留之前的筛选状态', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: _BookmarksListTestHost(
          topics: [
            _BookmarkSeed(id: 1, title: 'Alpha', bookmarkName: 'codex'),
            _BookmarkSeed(id: 2, title: 'Beta', bookmarkName: 'beta'),
            _BookmarkSeed(id: 3, title: 'Gamma', bookmarkName: 'codex'),
          ],
        ),
      ),
    );

    await tester.tap(find.text('codex (2)'));
    await tester.pumpAndSettle();

    final state = tester.state<_BookmarksListTestHostState>(
      find.byType(_BookmarksListTestHost),
    );
    state.hideSummaryBar();
    await tester.pumpAndSettle();

    expect(find.text('codex (2)'), findsNothing);
    expect(_findCardByTitle('Alpha'), findsOneWidget);
    expect(_findCardByTitle('Gamma'), findsOneWidget);
    expect(_findCardByTitle('Beta'), findsNothing);

    state.showSummaryBar();
    await tester.pumpAndSettle();

    expect(find.text('codex (2)'), findsOneWidget);
    expect(_findCardByTitle('Alpha'), findsOneWidget);
    expect(_findCardByTitle('Gamma'), findsOneWidget);
    expect(_findCardByTitle('Beta'), findsNothing);

    _stopMinuteClock();
  });

  testWidgets('桌面端可以拖动横向滚动顶部书签标签', (tester) async {
    PlatformUtils.debugDesktopOverride = true;
    addTearDown(() => PlatformUtils.debugDesktopOverride = null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: _BookmarksListTestHost(
          topics: List.generate(
            14,
            (index) => _BookmarkSeed(
              id: index + 1,
              title: 'Topic $index',
              bookmarkName: 'tag-$index',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summaryScrollable = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );

    expect(summaryScrollable.position.pixels, 0);

    await tester.drag(
      find.byKey(const ValueKey('bookmark-summary-wheel-region')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();

    expect(summaryScrollable.position.pixels, greaterThan(0));

    _stopMinuteClock();
  });

  testWidgets('桌面端滚轮会横向滚动顶部书签标签且不改选中项', (tester) async {
    PlatformUtils.debugDesktopOverride = true;
    addTearDown(() => PlatformUtils.debugDesktopOverride = null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: _BookmarksListTestHost(
          topics: List.generate(
            14,
            (index) => _BookmarkSeed(
              id: index + 1,
              title: 'Topic $index',
              bookmarkName: 'tag-$index',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<_BookmarksListTestHostState>(
      find.byType(_BookmarksListTestHost),
    );
    final summaryScrollable = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );
    expect(summaryScrollable.position.pixels, 0);
    expect(state._selectedBookmarkName, isNull);
    expect(state._scrollController.offset, 0);

    final region = find.byKey(const ValueKey('bookmark-summary-wheel-region'));
    final center = tester.getCenter(region);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: center);
    await tester.pump();

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 20),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();

    expect(summaryScrollable.position.pixels, greaterThan(0));
    expect(state._selectedBookmarkName, isNull);
    expect(state._scrollController.offset, 0);

    _stopMinuteClock();
  });

  testWidgets('手机端左右滑动标签下方内容会切换当前筛选项', (tester) async {
    PlatformUtils.debugDesktopOverride = false;
    addTearDown(() => PlatformUtils.debugDesktopOverride = null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: _BookmarksListTestHost(
          topics: const [
            _BookmarkSeed(id: 1, title: 'Alpha', bookmarkName: 'codex'),
            _BookmarkSeed(id: 2, title: 'Beta', bookmarkName: 'beta'),
            _BookmarkSeed(id: 3, title: 'Gamma', bookmarkName: 'codex'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<_BookmarksListTestHostState>(
      find.byType(_BookmarksListTestHost),
    );
    final swipeRegion = find.byKey(
      const ValueKey('bookmark-content-swipe-region'),
    );

    expect(state._selectedBookmarkName, isNull);

    await tester.drag(swipeRegion, const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(state._selectedBookmarkName, 'codex');
    expect(_findCardByTitle('Alpha'), findsOneWidget);
    expect(_findCardByTitle('Gamma'), findsOneWidget);
    expect(_findCardByTitle('Beta'), findsNothing);

    await tester.drag(swipeRegion, const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(state._selectedBookmarkName, 'beta');
    expect(_findCardByTitle('Beta'), findsOneWidget);
    expect(_findCardByTitle('Alpha'), findsNothing);

    await tester.drag(swipeRegion, const Offset(320, 0));
    await tester.pumpAndSettle();

    expect(state._selectedBookmarkName, 'codex');
    expect(_findCardByTitle('Alpha'), findsOneWidget);
    expect(_findCardByTitle('Gamma'), findsOneWidget);

    await tester.drag(swipeRegion, const Offset(320, 0));
    await tester.pumpAndSettle();

    expect(state._selectedBookmarkName, isNull);
    expect(_findCardByTitle('Alpha'), findsOneWidget);
    expect(_findCardByTitle('Beta'), findsOneWidget);
    expect(_findCardByTitle('Gamma'), findsOneWidget);

    _stopMinuteClock();
  });

  testWidgets('手机端左右拖动顶部名称标签只滚动标签条不切换筛选项', (tester) async {
    PlatformUtils.debugDesktopOverride = false;
    addTearDown(() => PlatformUtils.debugDesktopOverride = null);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 640));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: _BookmarksListTestHost(
          topics: List.generate(
            14,
            (index) => _BookmarkSeed(
              id: index + 1,
              title: 'Topic $index',
              bookmarkName: 'tag-$index',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<_BookmarksListTestHostState>(
      find.byType(_BookmarksListTestHost),
    );
    final summaryScrollable = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );

    expect(summaryScrollable.position.pixels, 0);
    expect(state._selectedBookmarkName, isNull);

    await tester.drag(
      find.byKey(const ValueKey('bookmark-summary-wheel-region')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();

    expect(summaryScrollable.position.pixels, greaterThan(0));
    expect(state._selectedBookmarkName, isNull);

    _stopMinuteClock();
  });
}

class _BookmarkSeed {
  const _BookmarkSeed({
    required this.id,
    required this.title,
    this.bookmarkName,
  });

  final int id;
  final String title;
  final String? bookmarkName;
}

class _BookmarksListTestHost extends StatefulWidget {
  const _BookmarksListTestHost({required this.topics});

  final List<_BookmarkSeed> topics;

  @override
  State<_BookmarksListTestHost> createState() => _BookmarksListTestHostState();
}

class _BookmarksListTestHostState extends State<_BookmarksListTestHost> {
  final ScrollController _scrollController = ScrollController();
  String? _selectedBookmarkName;
  bool _showSummaryBar = true;

  void hideSummaryBar() {
    setState(() => _showSummaryBar = false);
  }

  void showSummaryBar() {
    setState(() => _showSummaryBar = true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topics = widget.topics
        .map(
          (item) => _topic(
            id: item.id,
            title: item.title,
            bookmarkName: item.bookmarkName,
          ),
        )
        .toList();

    return TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: Scaffold(
          body: BookmarksListContent(
            bookmarksAsync: AsyncValue.data(topics),
            bookmarkNameSuggestions: const <String>[],
            bookmarkNameSuggestionsLoader: _emptySuggestionsLoader,
            scrollController: _scrollController,
            onRefresh: () async {},
            onTap: (_) {},
            onMiddleClick: (_) {},
            enableLongPress: false,
            showSummaryBar: _showSummaryBar,
            selectedBookmarkName: _selectedBookmarkName,
            onSelectedBookmarkName: (value) {
              setState(() => _selectedBookmarkName = value);
            },
            hasMore: false,
            isLoadMoreFailed: false,
            isLoadingMore: false,
            onRetryLoadMore: () {},
            onEditBookmark: (_) async {},
            onQuickRenameBookmark: (_, _) async => true,
            onClearReminder: (_) async {},
            onDeleteBookmark: (_) async {},
          ),
        ),
      ),
    );
  }
}

Future<List<String>> _emptySuggestionsLoader() async => const <String>[];

import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/app.dart';
import 'package:flashco/providers/config.dart';
import 'package:flashco/providers/database.dart';
import 'package:flashco/providers/state.dart';
import 'package:flashco/state.dart';
import 'package:flashco/ui/icons/icons.dart';
import 'package:flashco/ui/ui.dart';
import 'package:flashco/views/proxies/card.dart';
import 'package:flashco/views/proxies/group_tabs.dart';
import 'package:flashco/views/proxies/proxies.dart';
import 'package:flashco/views/proxies/tab.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';
import '../helpers/host_scaffold.dart';

final _tabStateProvider = NotifierProvider<_TabStateNotifier, ProxiesTabState>(
  _TabStateNotifier.new,
);

class _TabStateNotifier extends Notifier<ProxiesTabState> {
  @override
  ProxiesTabState build() => _tabState([_group('B'), _group('C')]);

  void set(ProxiesTabState value) => state = value;
}

void main() {
  late ProviderContainer globalContainer;
  late ProviderSubscription<Profile?> currentProfileSubscription;

  setUp(() {
    final profile = Profile.normal().copyWith(currentGroupName: 'B');
    globalContainer = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [_group('A'), _group('B'), _group('C')]),
        ),
        proxiesTabStateProvider.overrideWith(
          (ref) => ref.watch(_tabStateProvider),
        ),
      ],
    );
    globalState.container = globalContainer;
    currentProfileSubscription = globalContainer.listen(
      currentProfileProvider,
      (_, _) {},
    );
  });

  tearDown(() {
    currentProfileSubscription.close();
    globalContainer.dispose();
  });

  Future<GlobalKey<ProxiesTabViewState>> pumpTabView(
    WidgetTester tester,
  ) async {
    final key = GlobalKey<ProxiesTabViewState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: globalContainer,
        child: TestApp(
          child: ProxiesTabView(key: key),
          homeBuilder: (child) => HostScaffold(body: child),
        ),
      ),
    );
    await tester.pump();
    return key;
  }

  testWidgets('current group follows the tapped tab', (tester) async {
    final key = await pumpTabView(tester);

    expect(key.currentState?.currentGroup?.name, 'B');
    expect(isTabSelected(tester, 'B'), isTrue);

    await tester.tap(find.text('C'));
    await tester.pumpAndSettle();

    expect(key.currentState?.currentGroup?.name, 'C');
    expect(globalContainer.read(currentProfileProvider)?.currentGroupName, 'C');
    expect(isTabSelected(tester, 'C'), isTrue);
    expect(isTabSelected(tester, 'B'), isFalse);
  });

  testWidgets('a swipe between pages moves the selected tab', (tester) async {
    final key = await pumpTabView(tester);

    await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(key.currentState?.currentGroup?.name, 'C');
    expect(isTabSelected(tester, 'C'), isTrue);
    expect(isTabSelected(tester, 'B'), isFalse);
  });

  testWidgets('keeps the outgoing tabs usable while the empty state enters', (
    tester,
  ) async {
    final key = await pumpTabView(tester);

    globalContainer.read(_tabStateProvider.notifier).set(_tabState([]));
    await tester.pump();

    expect(find.text('C'), findsOneWidget);
    await tester.tap(find.text('C'), warnIfMissed: false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(key.currentState?.currentGroup, isNull);

    await tester.pumpAndSettle();

    expect(find.text('C'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the more button shows only once the tabs overflow', (
    tester,
  ) async {
    await pumpTabView(tester);

    expect(find.byGlyph(AppGlyphs.chevronDown), findsNothing);

    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([for (var i = 0; i < 12; i++) _group('Group $i')]));
    await tester.pumpAndSettle();

    expect(find.byGlyph(AppGlyphs.chevronDown), findsOneWidget);
  });

  testWidgets('opens with the current tab in view beside the more button', (
    tester,
  ) async {
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(
          _tabState([
            for (var i = 0; i < 12; i++) _group('Group $i'),
          ], current: 'Group 11'),
        );
    await pumpTabView(tester);
    await tester.pump();
    await tester.pump();

    final current = tester.getRect(tabOf('Group 11'));
    final more = tester.getRect(find.byGlyph(AppGlyphs.chevronDown));
    expect(isTabSelected(tester, 'Group 11'), isTrue);
    expect(current.right, lessThan(more.left));
  });

  testWidgets('horizontal group drags do not move a partially open sheet', (
    tester,
  ) async {
    const size = Size(400, 900);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: globalContainer,
        child: TestApp(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSnapSheet<void>(
                context,
                builder: (_, _) => Scaffold(
                  title: 'Groups',
                  body: Builder(
                    builder: (context) => Padding(
                      padding: EdgeInsets.only(top: context.contentTopPadding),
                      child: const Align(
                        alignment: Alignment.topCenter,
                        child: _SheetGroupTabs(),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    globalContainer.read(viewSizeProvider.notifier).value = size;
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final handle = find.byType(SheetDragHandle);
    final beforeTop = tester.getTopLeft(handle).dy;
    expect(beforeTop, closeTo(size.height * (1 - snapSheetDetents.first), 1));
    final scrollable = find.descendant(
      of: find.byType(GroupTabs),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final beforeOffset = position.pixels;
    await tester.drag(scrollable, const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(beforeOffset));
    expect(tester.getTopLeft(handle).dy, closeTo(beforeTop, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the last tab scrolls clear of the more button', (tester) async {
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([for (var i = 0; i < 12; i++) _group('Group $i')]));
    await pumpTabView(tester);
    await tester.pump();

    final tabs = find.descendant(
      of: find.byType(GroupTabs),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(tabs).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    final last = tester.getRect(tabOf('Group 11'));
    final more = tester.getRect(find.byGlyph(AppGlyphs.chevronDown));
    expect(last.right, lessThan(more.left));
  });

  testWidgets('the more menu stays short, opens on the checked current group '
      'and switches to the picked one', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(
          _tabState([
            for (var i = 0; i < 20; i++) _group('Group $i'),
          ], current: 'Group 12'),
        );
    final key = await pumpTabView(tester);
    await tester.pump();

    await tester.tap(find.byGlyph(AppGlyphs.chevronDown));
    await tester.pumpAndSettle();

    final menu = find.byType(PopupMenu);
    final check = find.descendant(
      of: menu,
      matching: find.byGlyph(AppGlyphs.check),
    );
    expect(check, findsOneWidget);
    expect(
      tester.getCenter(check).dy,
      closeTo(
        tester
            .getCenter(
              find.descendant(of: menu, matching: find.text('Group 12')),
            )
            .dy,
        1,
      ),
    );

    final card = tester.getRect(find.byType(PopupMenuCard));
    expect(card.height, lessThan(tester.view.physicalSize.height / 2));

    await tester.tap(
      find.descendant(of: menu, matching: find.text('Group 15')),
    );
    await tester.pumpAndSettle();

    expect(menu, findsNothing);
    expect(key.currentState?.currentGroup?.name, 'Group 15');
    expect(isTabSelected(tester, 'Group 15'), isTrue);
    final picked = tester.getRect(tabOf('Group 15'));
    final more = tester.getRect(find.byGlyph(AppGlyphs.chevronDown));
    expect(picked.left, greaterThanOrEqualTo(0));
    expect(picked.right, lessThan(more.left));
  });

  testWidgets('scroll to selected brings the row to the top of the grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [for (var i = 0; i < 80; i++) Proxy(name: 'B-$i', type: 'ss')],
    );
    globalContainer.read(groupsProvider.notifier).value = [group];
    final profile = globalContainer.read(currentProfileProvider)!;
    globalContainer
        .read(profilesProvider.notifier)
        .put(profile.copyWith(selectedMap: {'B': 'B-41'}));
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), group]));
    final key = await pumpTabView(tester);
    await tester.pumpAndSettle();
    final firstRowTop = tester
        .getRect(find.text('B-0', findRichText: true).first)
        .top;

    key.currentState?.scrollToGroupSelected();
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('B-41', findRichText: true).first).top,
      firstRowTop,
    );
  });

  testWidgets('cards rest where the grid clips them, clear of the tabs', (
    tester,
  ) async {
    final group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [for (var i = 0; i < 40; i++) Proxy(name: 'B-$i', type: 'ss')],
    );
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), group]));
    await pumpTabView(tester);
    await tester.pumpAndSettle();
    final tabs = tester.getRect(tabOf('B'));
    final grid = tester.getRect(find.byType(GridView));

    expect(grid.top, tabs.bottom + 16);
    expect(tester.getRect(find.byType(ProxyCard).first).top, grid.top);
  });

  testWidgets('a long press on a card offers to select it and to add it to '
      'the local proxies, one from a provider too', (tester) async {
    const group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [
        Proxy(name: 'B-0', type: 'ss'),
        Proxy(name: 'B-1', type: 'ss', providerName: 'sub'),
      ],
    );
    globalContainer.read(groupsProvider.notifier).value = [group];
    final profile = globalContainer.read(currentProfileProvider)!;
    globalContainer
        .read(profilesProvider.notifier)
        .put(profile.copyWith(selectedMap: {'B': 'B-0'}));
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), group]));
    await pumpTabView(tester);
    await tester.pumpAndSettle();
    final menu = find.byType(PopupMenu);

    await tester.longPress(find.text('B-0', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: menu, matching: find.text('Select')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.byGlyph(AppGlyphs.check)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Add to local proxies')),
      findsOneWidget,
    );

    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('B-1', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: menu, matching: find.text('Select')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Add to local proxies')),
      findsOneWidget,
    );
  });

  testWidgets('a custom profile offers to add only the proxies of a provider, '
      'as its own are the local proxies', (tester) async {
    const group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [
        Proxy(name: 'B-0', type: 'ss'),
        Proxy(name: 'B-1', type: 'ss', providerName: 'sub'),
      ],
    );
    globalContainer.read(groupsProvider.notifier).value = [group];
    final profile = globalContainer.read(currentProfileProvider)!;
    globalContainer
        .read(profilesProvider.notifier)
        .put(profile.copyWith(type: ProfileType.custom));
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), group]));
    await pumpTabView(tester);
    await tester.pumpAndSettle();
    final menu = find.byType(PopupMenu);

    await tester.longPress(find.text('B-0', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: menu, matching: find.text('Select')),
      findsOneWidget,
    );
    expect(find.text('Add to local proxies'), findsNothing);

    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('B-1', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: menu, matching: find.text('Add to local proxies')),
      findsOneWidget,
    );
  });

  testWidgets('a new current group leaves the visible cards as they were', (
    tester,
  ) async {
    final group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [for (var i = 0; i < 4; i++) Proxy(name: 'B-$i', type: 'ss')],
    );
    final state = _tabState([_group('A'), group]);
    globalContainer.read(_tabStateProvider.notifier).set(state);
    await pumpTabView(tester);
    final card = find.byType(ProxyCard).first;
    final before = tester.widget(card);

    globalContainer
        .read(_tabStateProvider.notifier)
        .set(state.copyWith(currentGroupName: 'A'));
    await tester.pump();

    expect(tester.widget(card), same(before));
  });

  testWidgets('lays each tab out at the width its label takes', (tester) async {
    const names = ['A', '🚀 节点选择', 'Group with a long name'];
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([for (final name in names) _group(name)], current: 'A'));
    await pumpTabView(tester);

    for (final name in names) {
      final tab = tabOf(name);
      expect(
        tester.getSize(tab).width,
        closeTo(
          tester
              .renderObject<RenderBox>(tab)
              .getMaxIntrinsicWidth(double.infinity),
          1,
        ),
        reason: name,
      );
    }
  });

  testWidgets('builds only the tabs in view and opens on a far current one', (
    tester,
  ) async {
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(
          _tabState([
            for (var i = 0; i < 200; i++) _group('Group $i'),
          ], current: 'Group 180'),
        );
    await pumpTabView(tester);
    await tester.pump();
    await tester.pump();

    expect(
      find
          .descendant(
            of: find.byType(GroupTabs),
            matching: find.byType(Card),
            skipOffstage: false,
          )
          .evaluate()
          .length,
      lessThan(30),
    );
    final current = tester.getRect(tabOf('Group 180'));
    final more = tester.getRect(find.byGlyph(AppGlyphs.chevronDown));
    expect(isTabSelected(tester, 'Group 180'), isTrue);
    expect(current.left, greaterThanOrEqualTo(0));
    expect(current.right, lessThan(more.left));
  });

  testWidgets('the bar following the current group leaves the page built', (
    tester,
  ) async {
    globalContainer
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.tab));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: globalContainer,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    await tester.pump();
    final tabs = tester.widget(find.byType(GroupTabs));

    final state = globalContainer.read(_tabStateProvider);
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(state.copyWith(currentGroupName: 'C'));
    globalContainer.read(delayTestingGroupsProvider.notifier).start('C');
    await tester.pump();

    expect(globalContainer.read(currentGroupDelayTestingProvider), isTrue);
    expect(tester.widget(find.byType(GroupTabs)), same(tabs));
  });

  testWidgets('rebuilds the tab bar when groups return', (tester) async {
    final key = await pumpTabView(tester);

    globalContainer.read(_tabStateProvider.notifier).set(_tabState([]));
    await tester.pumpAndSettle();
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), _group('B'), _group('C')]));
    await tester.pumpAndSettle();

    for (final name in ['A', 'B', 'C']) {
      expect(tabOf(name), findsOneWidget);
    }
    expect(key.currentState?.currentGroup?.name, 'B');
    expect(isTabSelected(tester, 'B'), isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _SheetGroupTabs extends StatefulWidget {
  const _SheetGroupTabs();

  @override
  State<_SheetGroupTabs> createState() => _SheetGroupTabsState();
}

class _SheetGroupTabsState extends State<_SheetGroupTabs>
    with SingleTickerProviderStateMixin {
  late final _groups = [for (var i = 0; i < 12; i++) _group('Group $i')];
  late final _controller = TabController(length: _groups.length, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      GroupTabs(controller: _controller, groups: _groups);
}

Finder tabOf(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card));

bool isTabSelected(WidgetTester tester, String name) =>
    tester.widget<Card>(tabOf(name)).isSelected;

ProxiesTabState _tabState(List<Group> groups, {String current = 'B'}) {
  return ProxiesTabState(
    groups: groups,
    currentGroupName: current,
    proxyCardType: ProxyCardType.standard,
  );
}

Group _group(String name) {
  return Group(type: GroupType.Selector, name: name);
}

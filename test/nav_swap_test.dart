import 'package:duanju_app/app_bottom_navigation.dart';
import 'package:duanju_app/downloads_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings lives at the bottom nav right edge and downloads moved '
      'into the overflow menu', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final repository = FixtureRepository();
    await tester.pumpWidget(
      DuanjuApp(repository: repository, store: store),
    );
    await tester.pumpAndSettle();

    // 底栏最右侧是「设置」而非「下载」。
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('下载'), findsNothing);

    // 停在「追剧」tab，点底栏「设置」直接推设置页。
    await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bottom-nav-3')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // 返回后底栏选中态仍留在「追剧」——设置是路由推送，不抢 tab。
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(
      tester
          .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
          .selectedIndex,
      1,
    );

    // 「下载」搬到右上角三点菜单，点它推下载页。
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('设置与备份'), findsNothing);
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);
  });
}

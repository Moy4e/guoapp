import 'package:duanju_app/player_interactions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'player_fixtures.dart';

PointerDownEvent _down(Offset position) => PointerDownEvent(
  pointer: 1,
  kind: PointerDeviceKind.touch,
  position: position,
);

PointerMoveEvent _move(Offset position) => PointerMoveEvent(
  pointer: 1,
  kind: PointerDeviceKind.touch,
  position: position,
);

PointerUpEvent _up(Offset position) => PointerUpEvent(
  pointer: 1,
  kind: PointerDeviceKind.touch,
  position: position,
);

/// 构造一个可用的 PlayerInteractions；viewHeight=200 时倍速锁定阈值为
/// clamp(200*0.22, 48, 112) = 48px
Future<PlayerInteractions> _mount(
  WidgetTester tester,
  Player player,
) async {
  final interactions = PlayerInteractions(
    player: player,
    available: () => true,
    baseSpeed: () => 1.0,
    onTogglePlayback: () {},
    onFullscreen: (_) {},
    onSeek: (_) async {},
  );
  await tester.pump();
  return interactions;
}

void main() {
  group('长按倍速锁定', () {
    testWidgets('上划锁定后保持倍速，不再弹恢复 1 倍速', (tester) async {
      final platform = ScriptedPlayer();
      final player = Player(platformPlayer: platform);
      await platform.playOrPause();
      final interactions = await _mount(tester, player);
      addTearDown(interactions.dispose);

      interactions.pointerDown(
        _down(const Offset(200, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(interactions.boosting, isTrue);
      expect(player.state.rate, 3.0);
      expect(interactions.speedLockHint, SpeedLockHint.swipeUpToLock);

      // 上滑 60px 越过 48px 阈值：进入预备态，且倍速不得被结束
      interactions.pointerMove(_move(const Offset(200, 140)));
      expect(interactions.boosting, isTrue);
      expect(interactions.speedLockHint, SpeedLockHint.releaseToLock);
      expect(player.state.rate, 3.0);

      // 松手提交锁定：倍速保持 3.0，不恢复 1.0
      interactions.pointerUp(_up(const Offset(200, 140)));
      await tester.pump();
      expect(interactions.speedLocked, isTrue);
      expect(player.state.rate, 3.0);
      expect(platform.rates.last, 3.0);
      expect(interactions.feedback, isEmpty);
      // 烧掉锁定提示的 2 秒瞬时定时器
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('锁定态再次长按不再调速，下滑解锁恢复原速', (tester) async {
      final platform = ScriptedPlayer();
      final player = Player(platformPlayer: platform);
      await platform.playOrPause();
      final interactions = await _mount(tester, player);
      addTearDown(interactions.dispose);

      interactions.pointerDown(
        _down(const Offset(200, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      interactions.pointerMove(_move(const Offset(200, 140)));
      interactions.pointerUp(_up(const Offset(200, 140)));
      await tester.pump();
      expect(interactions.speedLocked, isTrue);
      final ratesBefore = platform.rates.length;

      // 锁定态长按：不得再次 setRate，只提示下滑解锁
      interactions.pointerDown(
        _down(const Offset(200, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(platform.rates.length, ratesBefore);
      expect(player.state.rate, 3.0);
      expect(interactions.speedLockHint, SpeedLockHint.swipeDownToUnlock);

      // 下滑 60px 越过阈值：预备解锁
      interactions.pointerMove(_move(const Offset(200, 260)));
      expect(interactions.speedLockHint, SpeedLockHint.releaseToUnlock);

      interactions.pointerUp(_up(const Offset(200, 260)));
      await tester.pump();
      expect(interactions.speedLocked, isFalse);
      expect(player.state.rate, 1.0);
      expect(platform.rates.last, 1.0);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('锁定态长按后直接松开不改变锁定与倍速', (tester) async {
      final platform = ScriptedPlayer();
      final player = Player(platformPlayer: platform);
      await platform.playOrPause();
      final interactions = await _mount(tester, player);
      addTearDown(interactions.dispose);

      interactions.pointerDown(
        _down(const Offset(200, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      interactions.pointerMove(_move(const Offset(200, 140)));
      interactions.pointerUp(_up(const Offset(200, 140)));
      await tester.pump();
      expect(interactions.speedLocked, isTrue);

      interactions.pointerDown(
        _down(const Offset(200, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      interactions.pointerUp(_up(const Offset(200, 200)));
      await tester.pump();
      expect(interactions.speedLocked, isTrue);
      expect(player.state.rate, 3.0);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('未达长按时间就滑动不会触发倍速', (tester) async {
      final platform = ScriptedPlayer();
      final player = Player(platformPlayer: platform);
      await platform.playOrPause();
      final interactions = await _mount(tester, player);
      addTearDown(interactions.dispose);

      interactions.pointerDown(
        _down(const Offset(350, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      // 立即滑动：长按计时器应被取消，不进入倍速
      interactions.pointerMove(_move(const Offset(350, 180)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(interactions.boosting, isFalse);
      expect(platform.rates, isEmpty);
    });
  });

  group('音量手势', () {
    testWidgets('以起点快照推算，上滑不超过 100%', (tester) async {
      final platform = ScriptedPlayer();
      final player = Player(platformPlayer: platform);
      await platform.playOrPause();
      final interactions = await _mount(tester, player);
      addTearDown(interactions.dispose);

      interactions.pointerDown(
        _down(const Offset(350, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      // 右侧区域上滑：基准 100，任意上滑都被钳到 100
      interactions.pointerMove(_move(const Offset(350, 170)));
      await tester.pump();
      expect(interactions.hudState.type, SwipeAction.volume);
      expect(player.state.volume, 100.0);
      expect(interactions.hudState.value, 1.0);

      interactions.pointerMove(_move(const Offset(350, 100)));
      await tester.pump();
      expect(player.state.volume, lessThanOrEqualTo(100.0));
      expect(interactions.hudState.value, lessThanOrEqualTo(1.0));

      // 滑回中间：value = 100 - 100/100*100 = 0 → 静音
      interactions.pointerMove(_move(const Offset(350, 300)));
      await tester.pump();
      expect(player.state.volume, 0.0);
      expect(interactions.hudState.value, 0.0);
    });

    testWidgets('连续滑动显示与实际一致，不逐帧漂移', (tester) async {
      final platform = ScriptedPlayer();
      final player = Player(platformPlayer: platform);
      await platform.playOrPause();
      final interactions = await _mount(tester, player);
      addTearDown(interactions.dispose);

      interactions.pointerDown(
        _down(const Offset(350, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      // 首个移动仅判定分区（右侧=音量），HUD 显示起点音量 100%
      interactions.pointerMove(_move(const Offset(350, 180)));
      await tester.pump();
      expect(interactions.hudState.type, SwipeAction.volume);
      expect(player.state.volume, 100.0);
      expect(interactions.hudState.value, 1.0);

      // 下滑 20px：value = 100 - 20/100*100 = 80
      interactions.pointerMove(_move(const Offset(350, 220)));
      await tester.pump();
      expect(player.state.volume, closeTo(80.0, 0.001));
      expect(interactions.hudState.value, closeTo(0.8, 0.001));

      // 上滑越过 100%：value = 100 + 60 = 160 → 钳到 100（而非在 80 上叠加）
      interactions.pointerMove(_move(const Offset(350, 140)));
      await tester.pump();
      expect(player.state.volume, 100.0);

      // 再次下滑 20px：仍为 80，证明基准是手势起点快照、没有逐帧漂移
      interactions.pointerMove(_move(const Offset(350, 220)));
      await tester.pump();
      expect(player.state.volume, closeTo(80.0, 0.001));
      expect(interactions.hudState.value, closeTo(0.8, 0.001));
    });
  });

  group('亮度手势', () {
    testWidgets('以缓存亮度为基准，显示与实际一致', (tester) async {
      final platform = ScriptedPlayer();
      final player = Player(platformPlayer: platform);
      await platform.playOrPause();
      final interactions = await _mount(tester, player);
      addTearDown(interactions.dispose);

      interactions.pointerDown(
        _down(const Offset(50, 200)),
        swipeEnabled: true,
        width: 400,
        height: 200,
      );
      // 首个移动仅判定分区（左侧=亮度），HUD 显示缓存基准 50%
      interactions.pointerMove(_move(const Offset(50, 170)));
      expect(interactions.hudState.type, SwipeAction.brightness);
      expect(interactions.hudState.value, closeTo(0.5, 0.001));

      // 上滑 30px：level = 200*3 = 600 → 0.5 + 30/600 = 0.55
      interactions.pointerMove(_move(const Offset(50, 170)));
      await tester.pump();
      expect(interactions.hudState.value, closeTo(0.55, 0.001));
      expect(interactions.brightness, closeTo(0.55, 0.001));

      // 继续上滑到 60px：0.5 + 60/600 = 0.6，显示与实际同步跟随
      interactions.pointerMove(_move(const Offset(50, 140)));
      await tester.pump();
      expect(interactions.hudState.value, closeTo(0.6, 0.001));
      expect(interactions.brightness, closeTo(0.6, 0.001));

      // 下滑越过起点：0.5 - 60/600 = 0.4
      interactions.pointerMove(_move(const Offset(50, 260)));
      await tester.pump();
      expect(interactions.hudState.value, closeTo(0.4, 0.001));
      expect(interactions.brightness, closeTo(0.4, 0.001));
    });
  });
}

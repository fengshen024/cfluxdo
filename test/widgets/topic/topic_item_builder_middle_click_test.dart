import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/utils/platform_utils.dart';
import 'package:fluxdo/utils/relative_time_clock.dart';
import 'package:fluxdo/widgets/topic/painted_topic_card.dart';
import 'package:fluxdo/widgets/topic/topic_card_layout.dart';
import 'package:fluxdo/widgets/topic/topic_item_builder.dart';

Topic _topic() {
  return Topic(
    id: 1,
    title: 'Middle Click Topic',
    slug: 'middle-click-topic',
    postsCount: 1,
    replyCount: 0,
    views: 0,
    likeCount: 0,
    categoryId: '1',
  );
}

void main() {
  testWidgets('鼠标中键点击帖子会触发后台开标签回调', (tester) async {
    PlatformUtils.debugDesktopOverride = true;
    addTearDown(() => PlatformUtils.debugDesktopOverride = null);

    var middleClicked = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryMapProvider.overrideWith(
            (ref) => const AsyncValue.data(<int, Category>{}),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => buildTopicItem(
                context: context,
                topic: _topic(),
                isSelected: false,
                onTap: () {},
                onMiddleClick: () {
                  middleClicked = true;
                },
                enableLongPress: false,
              ),
            ),
          ),
        ),
      ),
    );

    // `buildTopicItem` 默认走自绘卡（kUsePaintedTopicCard）；widget 版
    // TopicCard 只在总开关回退时才出现，这里按实际渲染的卡类型取点
    final topicCard = find.byType(PaintedTopicCard);
    final center = tester.getCenter(topicCard);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    addTearDown(gesture.removePointer);
    await gesture.up();
    await tester.pump();

    expect(middleClicked, isTrue);

    // 自绘卡首次排版会挂上进程级分钟心跳（Timer 对齐到下一个分钟边界），
    // 不摘掉测试收尾会判定为残留 Timer。tearDown 跑在框架检查之后，来不及。
    TopicCardLayout.debugResetClockHook();
    RelativeTimeClock.instance.debugStop();
  });
}

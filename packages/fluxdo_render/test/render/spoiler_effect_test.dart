/// D2 守护:spoiler 遮罩效果(GPU shader 粒子)。
/// - reduce-motion(MediaQuery.disableAnimations):静态遮罩,无粒子 painter、无
///   Ticker(确保 golden/pumpAndSettle 能 settle)。
/// - 动画态:未揭示时挂 SpoilerEffectPainter(shader 粒子尘埃遮盖)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/render/spoiler_effect.dart';
import 'package:fluxdo_render/src/widget/fluxdo_render.dart';

void main() {
  Finder effectPainter() => find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SpoilerEffectPainter,
      );

  const spoilerHtml = '<p>答案 <span class="spoiler">42</span> 完</p>';

  testWidgets('reduce-motion:spoiler 静态遮罩,无粒子 painter(可 settle)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: true),
              child: const FluxdoRender(cookedHtml: spoilerHtml),
            ),
          ),
        ),
      ),
    );
    // 能 settle(无限 Ticker 被 reduce-motion 关掉)。
    await tester.pumpAndSettle();
    expect(effectPainter(), findsNothing,
        reason: 'reduce-motion 应走静态遮罩,不挂粒子 painter');
  });

  testWidgets('动画态:未揭示 spoiler 挂粒子 painter', (tester) async {
    // fromAsset 是真实异步 IO,fake-async 区内不会完成 → runAsync 预加载。
    await tester.runAsync(() => SpoilerShader.ensureLoaded());
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FluxdoRender(cookedHtml: spoilerHtml)),
      ),
    );
    await tester.pump(); // 布局
    await tester.pump(const Duration(milliseconds: 16)); // 推进一帧
    expect(effectPainter(), findsWidgets,
        reason: '动画态未揭示应挂 SpoilerEffectPainter');
    // 卸载以 dispose Ticker(避免活动 ticker 跨测试)。
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('点击揭开:涟漪动画 → 揭示;二次点击不回遮', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FluxdoRender(cookedHtml: spoilerHtml)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(effectPainter(), findsWidgets);

    // 点击 spoiler → 进入揭开动画:遮罩仍在(淡出中)+ 涟漪圆形裁剪。
    await tester.tap(find.text('42'));
    await tester.pump();
    expect(effectPainter(), findsWidgets, reason: '动画未结束,遮罩仍在淡出');
    expect(
      find.byWidgetPredicate(
          (w) => w is ClipPath && w.clipper is SpoilerRevealClipper),
      findsOneWidget,
      reason: '揭开动画应挂 SpoilerRevealClipper 圆形裁剪',
    );

    // 推进过动画时长(行内 spoiler 对角线小 → clamp 下限 250ms)→ 揭示态。
    await tester.pump(const Duration(milliseconds: 600));
    expect(effectPainter(), findsNothing, reason: '动画结束应完全揭示');

    // 二次点击不回遮(方便选中/复制)。
    await tester.tap(find.text('42'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(effectPainter(), findsNothing, reason: '揭示后不再回遮');
  });

  testWidgets('块级 spoiler:点击揭开 → 揭示后无回遮手势', (tester) async {
    const blockHtml = '<div class="spoiler"><p>secret</p></div>';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FluxdoRender(cookedHtml: blockHtml)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(effectPainter(), findsWidgets);

    // 块级内容藏在 Visibility(offstage)里,find.text 找不到 → 记遮罩中心,
    // 两次点击都用同一坐标。
    final center = tester.getCenter(effectPainter().first);
    await tester.tapAt(center);
    await tester.pump();
    // 块级 spoiler 宽度大 → 动画时长 250~550ms,推进 700ms 必结束。
    await tester.pump(const Duration(milliseconds: 700));
    expect(effectPainter(), findsNothing, reason: '动画结束应完全揭示');

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    expect(effectPainter(), findsNothing, reason: '揭示后不再回遮');
  });
}

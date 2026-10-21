import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/toc_extractor.dart';
import 'package:fluxdo_render/src/widget/heading_anchor.dart';

void main() {
  group('headingAnchorKey', () {
    test('chunkIndex 0 直接用 nodeId(短帖与长帖首 chunk 同口径)', () {
      expect(headingAnchorKey(0, 'b_2'), 'b_2');
      expect(headingAnchorKey(1, 'b_2'), '1:b_2');
      expect(headingAnchorKey(3, 'b_0'), '3:b_0');
    });
  });

  group('HeadingAnchorRegistry + Scope + Registrar', () {
    testWidgets('scope 内挂载注册、卸载注销;无 scope 零行为', (tester) async {
      final registry = HeadingAnchorRegistry();

      await tester.pumpWidget(
        HeadingAnchorScope(
          registry: registry,
          child: const Column(
            children: [
              HeadingAnchorRegistrar(
                nodeId: 'b_1',
                child: SizedBox(key: Key('h1')),
              ),
              HeadingAnchorRegistrar(
                nodeId: 'b_2',
                chunkIndex: 2,
                child: SizedBox(key: Key('h2')),
              ),
            ],
          ),
        ),
      );

      expect(registry.contextOf('b_1'), isNotNull);
      expect(registry.contextOf('2:b_2'), isNotNull);
      // 复合键与原始 id 不混用
      expect(registry.contextOf('b_2'), isNull);
      expect(find.byKey(const Key('h1')), findsOneWidget);

      // 卸载后注销
      await tester.pumpWidget(
        HeadingAnchorScope(registry: registry, child: const SizedBox()),
      );
      expect(registry.contextOf('b_1'), isNull);
      expect(registry.contextOf('2:b_2'), isNull);
    });

    testWidgets('无 scope 时 Registrar 是透明包装', (tester) async {
      await tester.pumpWidget(
        const HeadingAnchorRegistrar(
          nodeId: 'b_0',
          child: SizedBox(key: Key('plain')),
        ),
      );
      expect(find.byKey(const Key('plain')), findsOneWidget);
    });

    testWidgets('registry 替换时迁移注册(scope 实例更换)', (tester) async {
      final r1 = HeadingAnchorRegistry();
      final r2 = HeadingAnchorRegistry();

      Widget app(HeadingAnchorRegistry r) => HeadingAnchorScope(
            registry: r,
            child: const HeadingAnchorRegistrar(
              nodeId: 'b_0',
              child: SizedBox(),
            ),
          );

      await tester.pumpWidget(app(r1));
      expect(r1.contextOf('b_0'), isNotNull);

      await tester.pumpWidget(app(r2));
      expect(r1.contextOf('b_0'), isNull);
      expect(r2.contextOf('b_0'), isNotNull);
    });
  });
}

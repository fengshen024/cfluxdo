// CLI 入口 —— 实际逻辑在 _meta/validator.dart,这样可以被 flutter test 直接调用。
//
// 用法(在 packages/fluxdo_render 目录下):
//   dart run test/fixtures/scripts/validate.dart
//   dart run test/fixtures/scripts/validate.dart --fix-sha

import 'dart:io';

import '../_meta/validator.dart';

void main(List<String> args) {
  final fixSha = args.contains('--fix-sha');
  final root = Directory('test/fixtures');
  if (!root.existsSync()) {
    stderr.writeln('请在 packages/fluxdo_render 目录下运行');
    exit(1);
  }
  final report = validateFixtures(root, fixSha: fixSha);
  if (report.ok) {
    stdout.writeln('✓ 已检查 ${report.checked} 个 fixture,全部合法');
    exit(0);
  } else {
    stderr.writeln('✗ 已检查 ${report.checked} 个 fixture,${report.errors.length} 个错误:');
    for (final e in report.errors) {
      stderr.writeln('  - $e');
    }
    exit(1);
  }
}

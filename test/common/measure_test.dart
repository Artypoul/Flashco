import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/measure.dart';
import 'package:prism_ui/typography.dart';
import 'package:prism_ui/text.dart';
import 'package:prism_ui/tooltip.dart';

import '../helpers/test_app.dart';
import '../helpers/host_scaffold.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Measure> _measureIn(WidgetTester tester, {double scale = 1}) async {
  late Measure measure;
  await tester.pumpWidget(
    HostApp(
      home: Builder(
        builder: (context) {
          measure = Measure.of(context, scale);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return measure;
}

void main() {
  testWidgets('sizes grow with the text scale factor', (tester) async {
    final single = await _measureIn(tester);
    final baseline = single.computeTextSize(const Text('Flashco'));

    final doubled = await _measureIn(tester, scale: 2);
    final scaled = doubled.computeTextSize(const Text('Flashco'));

    expect(scaled.width, greaterThan(baseline.width));
    expect(scaled.height, greaterThan(baseline.height));
  });

  testWidgets('an explicit style overrides the size of an unstyled text', (
    tester,
  ) async {
    final measure = await _measureIn(tester);
    final small = measure.computeTextSize(
      const Text('Flashco', style: TextStyle(fontSize: 10)),
    );
    final large = measure.computeTextSize(
      const Text('Flashco', style: TextStyle(fontSize: 40)),
    );
    expect(large.width, greaterThan(small.width));
  });

  testWidgets('overflow is reported only when the text cannot fit', (
    tester,
  ) async {
    const text = 'a considerably longer run of text';
    Future<void> show(double width) async {
      await tester.pumpWidget(
        TestApp(
          child: HostScaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: const TooltipText(text: Text(text, maxLines: 1)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show(2000);
    expect(
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines,
      isFalse,
    );
    expect(
      find.descendant(
        of: find.byType(TooltipText),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
    await show(10);
    expect(
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines,
      isTrue,
    );
    expect(find.byTooltip(text), findsOneWidget);
  });

  testWidgets('repeated measurement releases each painter', (tester) async {
    final measure = await _measureIn(tester);
    // A leaked TextPainter holds a native paragraph; the framework's leak
    // tracker turns that into an exception here rather than into drift that
    // only shows up while scrolling a long proxy list.
    for (var i = 0; i < 50; i++) {
      measure.computeTextSize(Text('row $i'));
    }
    expect(tester.takeException(), null);
  });

  testWidgets('cached text metrics are computed once and reused', (
    tester,
  ) async {
    final measure = await _measureIn(tester);
    final subheadline = measure.textHeight(AppTextStyle.subheadline);
    expect(subheadline, greaterThan(0));
    expect(measure.textHeight(AppTextStyle.subheadline), subheadline);
    expect(
      measure.textHeight(AppTextStyle.body),
      greaterThan(measure.textHeight(AppTextStyle.footnote)),
    );
  });
}

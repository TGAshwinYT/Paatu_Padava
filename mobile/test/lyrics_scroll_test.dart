import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ListView.builder jumping to estimated offset mounts target child and allows ensureVisible', (tester) async {
    final scrollController = ScrollController();
    final keys = List.generate(50, (_) => GlobalKey());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.only(top: 200, bottom: 300),
              itemCount: 50,
              itemBuilder: (context, index) {
                return Container(
                  key: keys[index],
                  height: 60,
                  alignment: Alignment.center,
                  child: Text('Line $index'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify item 0 is mounted and item 30 is NOT mounted initially
    expect(keys[0].currentContext, isNotNull);
    expect(keys[30].currentContext, isNull);

    // Calculate estimated offset for line 30
    const targetIdx = 30;
    final viewportHeight = scrollController.position.viewportDimension;
    const topPadding = 200.0;
    final estimatedOffset = (topPadding + (targetIdx * 60.0)) - (viewportHeight * 0.45);

    scrollController.jumpTo(estimatedOffset.clamp(0.0, scrollController.position.maxScrollExtent));
    await tester.pumpAndSettle();

    // Verify line 30 is mounted
    expect(keys[targetIdx].currentContext, isNotNull);

    // Verify ensureVisible works on it
    await Scrollable.ensureVisible(
      keys[targetIdx].currentContext!,
      alignment: 0.45,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();

    expect(find.text('Line 30'), findsOneWidget);
  });

  testWidgets('Lyrics auto-scroll pauses on user scroll and resumes after 10 seconds of idle time', (tester) async {
    bool isUserScrolling = false;
    Timer? userScrollResumeTimer;
    int resumeCount = 0;

    void onUserScrollStart() {
      isUserScrolling = true;
      userScrollResumeTimer?.cancel();
    }

    void onUserScrollEnd() {
      if (!isUserScrolling) return;
      userScrollResumeTimer?.cancel();
      userScrollResumeTimer = Timer(const Duration(seconds: 10), () {
        isUserScrolling = false;
        resumeCount++;
      });
    }

    // 1. User starts scrolling
    onUserScrollStart();
    expect(isUserScrolling, isTrue);
    expect(resumeCount, equals(0));

    // 2. User finishes scrolling gesture
    onUserScrollEnd();
    expect(isUserScrolling, isTrue);

    // 3. Advance 5 seconds - should NOT have resumed yet (still within 10s idle period)
    await tester.pump(const Duration(seconds: 5));
    expect(isUserScrolling, isTrue);
    expect(resumeCount, equals(0));

    // 4. Advance another 4 seconds (total 9s) - still waiting
    await tester.pump(const Duration(seconds: 4));
    expect(isUserScrolling, isTrue);
    expect(resumeCount, equals(0));

    // 5. Advance 1 more second (total 10s) - idle timer fires and resumes auto-scroll
    await tester.pump(const Duration(seconds: 1));
    expect(isUserScrolling, isFalse);
    expect(resumeCount, equals(1));

    // 6. Test gesture interrupt: user scrolls, waits 7s, scrolls again, then waits 10s
    onUserScrollStart();
    onUserScrollEnd();
    await tester.pump(const Duration(seconds: 7));
    expect(isUserScrolling, isTrue);
    expect(resumeCount, equals(1)); // Has not fired second time

    // User touches again before 10s
    onUserScrollStart();
    expect(isUserScrolling, isTrue);

    // User releases
    onUserScrollEnd();
    await tester.pump(const Duration(seconds: 8));
    expect(isUserScrolling, isTrue); // 8s passed since restart, still waiting
    expect(resumeCount, equals(1));

    // Advance 2 more seconds (total 10s since last interaction)
    await tester.pump(const Duration(seconds: 2));
    expect(isUserScrolling, isFalse);
    expect(resumeCount, equals(2));

    userScrollResumeTimer?.cancel();
  });
}

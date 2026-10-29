import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone profile used to render screens at realistic sizes.
class DeviceProfile {
  final String name;
  final Size logicalSize; // in logical pixels (dp)
  final double pixelRatio;
  final EdgeInsets safeArea; // status bar / notch / gesture bar, in dp

  const DeviceProfile(this.name, this.logicalSize, this.pixelRatio, this.safeArea);

  @override
  String toString() => '$name ${logicalSize.width.toInt()}x${logicalSize.height.toInt()}';
}

/// Small -> large. The small phone + big text combination is where most
/// "broken UI" (overflow stripes, clipped buttons) shows up first.
const List<DeviceProfile> kDevices = [
  DeviceProfile('small-phone', Size(360, 640), 2.0, EdgeInsets.only(top: 24, bottom: 0)),
  DeviceProfile('regular-phone', Size(390, 844), 3.0, EdgeInsets.only(top: 47, bottom: 34)),
  DeviceProfile('large-phone', Size(430, 932), 3.0, EdgeInsets.only(top: 54, bottom: 34)),
  DeviceProfile('tablet', Size(800, 1280), 2.0, EdgeInsets.only(top: 24, bottom: 0)),
];

/// 1.0 = default, 1.5 = what many users set under Android "Font size".
const List<double> kTextScales = [1.0, 1.5];

/// Error text fragments that mean "the layout is broken".
const List<String> _layoutErrorMarkers = [
  'overflowed',
  'RenderFlex',
  'RenderBox was not laid out',
  'unbounded',
  'BoxConstraints forces an infinite',
  'Vertical viewport was given unbounded',
  'RenderViewport',
  'A RenderFlex',
];

bool isLayoutError(String message) =>
    _layoutErrorMarkers.any((m) => message.contains(m));

class LayoutReport {
  final List<String> layoutErrors;
  final List<String> otherErrors;
  const LayoutReport(this.layoutErrors, this.otherErrors);
  bool get hasLayoutErrors => layoutErrors.isNotEmpty;
}

/// Pumps [screen] on [device] at [textScale] and returns everything the
/// framework complained about while building/laying out.
///
/// Uses bounded pumps (not pumpAndSettle) because several screens run
/// endless animations (mesh gradients, progress indicators).
Future<LayoutReport> pumpAndCollectLayoutErrors(
  WidgetTester tester,
  Widget screen, {
  required DeviceProfile device,
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  final view = tester.view;
  view.physicalSize = Size(
    device.logicalSize.width * device.pixelRatio,
    device.logicalSize.height * device.pixelRatio,
  );
  view.devicePixelRatio = device.pixelRatio;
  final padding = FakeViewPadding(
    top: device.safeArea.top * device.pixelRatio,
    bottom: device.safeArea.bottom * device.pixelRatio,
    left: device.safeArea.left * device.pixelRatio,
    right: device.safeArea.right * device.pixelRatio,
  );
  view.padding = padding;
  view.viewPadding = padding;
  addTearDown(() {
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    view.resetPadding();
    view.resetViewPadding();
  });

  final layoutErrors = <String>[];
  final otherErrors = <String>[];
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final text = details.exceptionAsString();
    (isLayoutError(text) ? layoutErrors : otherErrors).add(text.split('\n').first);
  };

  try {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? ThemeData.dark(),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          );
        },
        home: screen,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  } finally {
    FlutterError.onError = previousHandler;
    tester.takeException(); // clear anything the binding captured itself
  }

  return LayoutReport(layoutErrors, otherErrors);
}

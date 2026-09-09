import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_application_1/screens/chat_camera_screen.dart';
import 'package:flutter_application_1/services/app_strings.dart';

const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);
const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// A [CameraPlatform] that answers entirely in Dart.
///
/// Every method on the real platform interface throws `UnimplementedError` by
/// default, so overriding the handful the screen touches is enough — and it
/// keeps `availableCameras()` off an unregistered method channel, which in a
/// widget test would otherwise hand back a future the fake clock never
/// completes.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({required this.capturePath});

  /// The file [takePicture] hands back.
  final String capturePath;

  List<CameraDescription> cameras = const [_back, _front];

  /// Thrown from `createCameraWithSettings`, i.e. what `initialize()` reports.
  Object? createError;

  /// Thrown from `setFlashMode`, standing in for a lens with no flash.
  Object? flashError;

  /// Thrown from `takePicture`.
  Object? captureError;

  /// When set, `takePicture` waits on it, so a test can hold a capture open.
  Completer<void>? captureGate;

  /// When set, `availableCameras` waits on it, so a test can hold the whole
  /// bootstrap open and look at the loading state.
  Completer<void>? camerasGate;

  int createCalls = 0;
  int disposeCalls = 0;
  int takePictureCalls = 0;
  final List<CameraDescription> created = [];
  final List<FlashMode> flashModes = [];
  final List<DeviceOrientation> lockedOrientations = [];

  /// A stream that never emits and never closes.
  ///
  /// `CameraController.initialize` calls `.first` on `onCameraError` and
  /// discards the future; on an empty stream that `.first` throws
  /// `StateError`, which surfaces as an unhandled async error and fails the
  /// test for reasons that have nothing to do with the screen.
  Stream<T> _silent<T>() => StreamController<T>.broadcast().stream;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (camerasGate != null) await camerasGate!.future;
    return cameras;
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async {
    createCalls++;
    created.add(cameraDescription);
    if (createError != null) throw createError!;
    return createCalls;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1080,
          1920,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _silent();

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      _silent();

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {
    lockedOrientations.add(orientation);
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (flashError != null) throw flashError!;
    flashModes.add(mode);
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    takePictureCalls++;
    if (captureGate != null) await captureGate!.future;
    if (captureError != null) throw captureError!;
    return XFile(capturePath);
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(
    key: ValueKey('fake-camera-texture'),
    color: Color(0xFF203040),
  );

  @override
  Future<void> dispose(int cameraId) async {
    disposeCalls++;
  }
}

void main() {
  late Directory temp;
  late _FakeCameraPlatform fake;
  late CameraPlatform original;

  /// Records every call the screen makes to the pixel normalizer, so the tests
  /// can assert the mirror *policy* without spawning the real isolate.
  late List<({String path, bool mirror})> normalizeCalls;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('chat_camera_test');
    final capture = File('${temp.path}/CAP_test.jpg')
      ..writeAsBytesSync(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90),
      );
    fake = _FakeCameraPlatform(capturePath: capture.path);
    original = CameraPlatform.instance;
    CameraPlatform.instance = fake;
    normalizeCalls = [];
    debugResetChatCameraMemory();
    addTearDown(() {
      CameraPlatform.instance = original;
      debugResetChatCameraMemory();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
  });

  /// Pumps a host screen and opens the camera, recording what it pops.
  ///
  /// The surface matters: the screen pins the capture to portrait only on a
  /// phone-sized window, and `flutter_test`'s default 800x600 would read as a
  /// tablet.
  Future<({XFile? Function() shot, bool Function() done})> openCamera(
    WidgetTester tester, {
    Size logicalSize = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = logicalSize;
    addTearDown(tester.view.reset);
    XFile? popped;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('open-camera'),
            onPressed: () async {
              popped = await Navigator.of(context).push<XFile>(
                MaterialPageRoute(
                  builder: (_) => ChatCameraScreen(
                    normalizeCapture: (path, {required bool mirror}) async {
                      normalizeCalls.add((path: path, mirror: mirror));
                      return true;
                    },
                  ),
                ),
              );
              done = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-camera')));
    return (shot: () => popped, done: () => done);
  }

  testWidgets('the loading placeholder settles', (tester) async {
    fake.camerasGate = Completer<void>();
    await openCamera(tester);
    // Settling with the bootstrap held open is the assertion: the placeholder
    // runs no animation, so this returns. An indeterminate progress indicator
    // here would spin forever and time the settle out.
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-camera-loading')), findsOneWidget);
    expect(find.byType(CameraPreview), findsNothing);

    fake.camerasGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-camera-loading')), findsNothing);
    expect(find.byKey(const ValueKey('chat-camera-preview')), findsOneWidget);
  });

  testWidgets('a ready camera draws its viewfinder and controls', (
    tester,
  ) async {
    await openCamera(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-camera-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-preview')), findsOneWidget);
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-shutter')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-flip')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-error')), findsNothing);
    // The rear lens opens first, exactly as the old system camera did.
    expect(fake.created.single.lensDirection, CameraLensDirection.back);
    // A phone-sized surface pins the capture to portrait, and the flash starts
    // off rather than at the platform's own default.
    expect(fake.lockedOrientations, [DeviceOrientation.portraitUp]);
    expect(fake.flashModes, [FlashMode.off]);
  });

  testWidgets('the selfie flash starts off and uses the same toggle', (tester) async {
    await openCamera(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-camera-flash')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-camera-flip')));
    await tester.pumpAndSettle();
    expect(fake.created.last.lensDirection, CameraLensDirection.front);
    expect(find.byKey(const ValueKey('chat-camera-flash')), findsOneWidget);
    expect(fake.flashModes, [FlashMode.off, FlashMode.off]);

    for (final mode in [FlashMode.auto, FlashMode.always, FlashMode.off]) {
      await tester.tap(find.byKey(const ValueKey('chat-camera-flash')));
      await tester.pumpAndSettle();
      expect(fake.flashModes.last, mode);
    }

    expect(find.byTooltip(S.flashOff), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-camera-flip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-camera-flash')), findsOneWidget);
    expect(fake.flashModes.last, FlashMode.off);
  });

  testWidgets('a lens with no flash simply has no toggle', (tester) async {
    fake.flashError = CameraException('setFlashModeFailed', 'no flash');
    await openCamera(tester);
    await tester.pumpAndSettle();

    // A flash failure is not an init failure: the camera still works.
    expect(find.byKey(const ValueKey('chat-camera-shutter')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-flash')), findsNothing);
    expect(find.byKey(const ValueKey('chat-camera-error')), findsNothing);
  });

  testWidgets('the flash toggle cycles off, auto, on', (tester) async {
    await openCamera(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-camera-flash')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-camera-flash')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-camera-flash')));
    await tester.pumpAndSettle();

    expect(fake.flashModes, [
      FlashMode.off,
      FlashMode.auto,
      FlashMode.always,
      FlashMode.off,
    ]);
  });

  testWidgets('a selfie is mirrored once and popped', (tester) async {
    final result = await openCamera(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-camera-flip')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-camera-shutter')));
    await tester.pumpAndSettle();

    expect(normalizeCalls, hasLength(1));
    expect(normalizeCalls.single.mirror, isTrue);
    expect(normalizeCalls.single.path, fake.capturePath);
    expect(result.done(), isTrue);
    expect(result.shot()?.path, fake.capturePath);
  });

  testWidgets('a rear capture is baked upright but never mirrored', (
    tester,
  ) async {
    final result = await openCamera(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-camera-shutter')));
    await tester.pumpAndSettle();

    expect(normalizeCalls, hasLength(1));
    expect(normalizeCalls.single.mirror, isFalse);
    expect(result.shot()?.path, fake.capturePath);
  });

  testWidgets('a second shutter tap during a capture is ignored', (
    tester,
  ) async {
    fake.captureGate = Completer<void>();
    final result = await openCamera(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-camera-shutter')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-camera-shutter')));
    await tester.pump();

    expect(fake.takePictureCalls, 1);
    expect(find.byKey(const ValueKey('chat-camera-processing')), findsOneWidget);

    fake.captureGate!.complete();
    await tester.pumpAndSettle();

    expect(normalizeCalls, hasLength(1));
    expect(result.shot()?.path, fake.capturePath);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lens cannot be flipped mid-capture', (tester) async {
    fake.captureGate = Completer<void>();
    await openCamera(tester);
    await tester.pumpAndSettle();
    final createsBefore = fake.createCalls;

    await tester.tap(find.byKey(const ValueKey('chat-camera-shutter')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-camera-flip')));
    await tester.pump();

    expect(fake.createCalls, createsBefore);

    fake.captureGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the screen cannot be closed mid-capture', (tester) async {
    // Closing here used to pop twice: once for the camera, and again from
    // _capture when the bake finished, which took the chat thread with it.
    fake.captureGate = Completer<void>();
    final result = await openCamera(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-camera-shutter')));
    await tester.pump();

    final close = tester.widget<IconButton>(
      find.byKey(const ValueKey('chat-camera-close')),
    );
    expect(close.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('chat-camera-close')));
    await tester.pump();
    expect(result.done(), isFalse, reason: 'the capture still owns the route');

    fake.captureGate!.complete();
    await tester.pumpAndSettle();

    // Exactly one pop, carrying the photo.
    expect(result.done(), isTrue);
    expect(result.shot()?.path, fake.capturePath);
    expect(find.byKey(const ValueKey('chat-camera-screen')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed capture keeps the camera open and says so', (
    tester,
  ) async {
    fake.captureError = CameraException('captureFailed', 'nope');
    final result = await openCamera(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-camera-shutter')));
    await tester.pumpAndSettle();

    expect(find.text(S.cameraCaptureFailed), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-shutter')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-preview')), findsOneWidget);
    expect(normalizeCalls, isEmpty);
    expect(result.done(), isFalse, reason: 'the screen stays open');
    // Outlast the snack bar so its timer does not fire after the test.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('backgrounding releases the camera and resuming rebuilds it', (
    tester,
  ) async {
    await openCamera(tester);
    await tester.pumpAndSettle();
    expect(fake.createCalls, 1);

    // The real sequence a backgrounded app sees. `inactive` comes first and is
    // where the camera has to go: it is also the last state that still renders
    // frames, because SchedulerBinding turns frames off from `hidden` onward.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    // A preview resumed over a disposed controller is a black rectangle, so
    // the controller has to be gone here and rebuilt below.
    expect(find.byType(CameraPreview), findsNothing);
    expect(find.byKey(const ValueKey('chat-camera-loading')), findsOneWidget);
    expect(fake.disposeCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(fake.disposeCalls, 1, reason: 'nothing left to release');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(CameraPreview), findsOneWidget);
    // Two creates, one dispose: the resume waited for the teardown instead of
    // opening a second camera alongside the closing one.
    expect(fake.createCalls, 2);
    expect(fake.disposeCalls, 1);
  });

  testWidgets('a camera built while the app was away is replaced', (
    tester,
  ) async {
    // Backgrounding inside the initialization window used to leave a
    // controller attached to a session the OS had already interrupted, which
    // shows up as a preview that is simply black.
    fake.camerasGate = Completer<void>();
    await openCamera(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-camera-loading')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    // The start in flight is left alone on purpose: iOS holds the app
    // inactive while its own permission alert is up.
    fake.camerasGate!.complete();
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-camera-preview')), findsOneWidget);
    expect(fake.createCalls, 2, reason: 'the interrupted camera was replaced');
    expect(fake.disposeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a denied permission offers a way into Settings', (tester) async {
    fake.createError = PlatformException(
      code: 'CameraAccessDenied',
      message: 'denied',
    );
    final result = await openCamera(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-camera-error')), findsOneWidget);
    expect(find.text(S.cameraPermissionTitle), findsOneWidget);
    expect(find.text(S.cameraPermissionBody), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-camera-open-settings')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-camera-shutter')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-camera-error-cancel')));
    await tester.pumpAndSettle();
    expect(result.done(), isTrue);
    expect(result.shot(), isNull);
  });

  testWidgets('a device restriction offers no Settings shortcut', (
    tester,
  ) async {
    fake.createError = PlatformException(
      code: 'CameraAccessRestricted',
      message: 'restricted',
    );
    await openCamera(tester);
    await tester.pumpAndSettle();

    expect(find.text(S.cameraRestrictedBody), findsOneWidget);
    // Settings cannot lift a restriction, so offering it would be a dead end.
    expect(find.byKey(const ValueKey('chat-camera-open-settings')), findsNothing);
  });

  testWidgets('a device with no cameras says so', (tester) async {
    // What the iOS Simulator reports.
    fake.cameras = const [];
    await openCamera(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-camera-error')), findsOneWidget);
    expect(find.text(S.cameraUnavailableBody), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-camera-open-settings')), findsNothing);
    expect(fake.createCalls, 0);
  });

  testWidgets('the shutter sits at the bottom, not the middle of the screen', (
    tester,
  ) async {
    // It shipped once in the dead centre of the display: `Center` inside the
    // control row has no height factor, so it grew to fill the loose vertical
    // constraint and took the row with it. The row's height is what pins it.
    await openCamera(tester);
    await tester.pumpAndSettle();

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final shutter = tester.getRect(
      find.byKey(const ValueKey('chat-camera-shutter')),
    );

    expect(shutter.center.dx, screen.width / 2, reason: 'horizontally centred');
    expect(
      shutter.center.dy,
      greaterThan(screen.height * 0.8),
      reason: 'in the bottom band, where a camera app puts it',
    );
    expect(shutter.bottom, lessThanOrEqualTo(screen.height));

    // The lens flip shares that band, and the close button stays up top.
    final flip = tester.getRect(find.byKey(const ValueKey('chat-camera-flip')));
    expect(flip.center.dy, closeTo(shutter.center.dy, 1));
    expect(flip.center.dx, greaterThan(shutter.center.dx));
    final close = tester.getRect(
      find.byKey(const ValueKey('chat-camera-close')),
    );
    expect(close.center.dy, lessThan(screen.height * 0.2));
  });

  testWidgets('a tablet-sized window keeps its rotation', (tester) async {
    // An iPad really does rotate, so pinning its capture to portrait would
    // fight the interface instead of matching it.
    await openCamera(tester, logicalSize: const Size(834, 1194));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-camera-preview')), findsOneWidget);
    expect(fake.lockedOrientations, isEmpty);
  });

  testWidgets('a single-lens device hides the flip control', (tester) async {
    fake.cameras = const [_back];
    await openCamera(tester);
    await tester.pumpAndSettle();

    final flip = tester.widget<IconButton>(
      find.byKey(const ValueKey('chat-camera-flip')),
    );
    expect(flip.onPressed, isNull);
  });
}

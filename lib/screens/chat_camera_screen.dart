/// The chat camera: a viewfinder inside the app, so a photo goes straight from
/// the shutter to the app's own send screen.
///
/// It exists because iOS's `UIImagePickerController` always inserts its own
/// Retake/Use Photo step after the shutter — `image_picker` sets only
/// `sourceType` and `cameraDevice`, and UIKit exposes no way off that screen —
/// and this app already has [MediaPreviewScreen] for confirming a photo.
///
/// It also makes selfies deterministic. The `camera` plugin mirrors the front
/// *viewfinder* on both platforms (iOS sets `isVideoMirrored` on the preview
/// connection only; Android mirrors the preview widget) and never mirrors the
/// saved file. Because this screen knows which lens fired, it can flip the
/// pixels so the photo that gets sent is the one the user framed, instead of
/// guessing from an EXIF lens model the way the system-camera path had to.
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/capture_normalizer.dart';

/// Whether the `camera` plugin mirrors the front-camera viewfinder for us.
///
/// True on iOS (`camera_avfoundation` sets `isVideoMirrored` on the preview
/// connection) and on both of Android's preview paths (in Dart on the
/// ImageReader path, natively on the Impeller path since
/// `camera_android_camerax` 0.6.18+3). If a device ever shows a true-to-life
/// front viewfinder, set this to false: it mirrors the preview widget instead,
/// so the viewfinder and the baked photo can never disagree.
const bool _pluginMirrorsFrontPreview = true;

/// Lens and flash chosen last, remembered for the life of the process.
///
/// Not persisted: a fresh launch starting on the rear lens with the flash off
/// is the predictable default, and the capture path should not write to disk.
CameraLensDirection _lastLens = CameraLensDirection.back;
FlashMode _lastFlashMode = FlashMode.off;

/// Forgets [_lastLens] and [_lastFlashMode] so tests start from the default.
@visibleForTesting
void debugResetChatCameraMemory() {
  _lastLens = CameraLensDirection.back;
  _lastFlashMode = FlashMode.off;
}

/// Diameter of the shutter, and therefore the height of the row holding it.
const double _shutterDiameter = 72;

/// How long to wait for a capture before giving the user a way out.
///
/// iOS drops the reply if the camera is deallocated mid-capture (its
/// completion handler bails on a released `self`), which would otherwise leave
/// the screen waiting on a future that never completes.
const Duration _captureTimeout = Duration(seconds: 10);

enum _Stage { loading, ready, capturing, processing, failed }

enum _Failure {
  /// No camera on the device, or one that would not start for any other
  /// reason. Nothing the user can do here.
  unavailable,

  /// Camera access is off. Reachable from Settings, so the screen offers that
  /// and retries by itself when the app comes back.
  denied,

  /// Camera use is blocked by a device restriction. Settings cannot fix it.
  restricted,
}

/// Pops with the captured [XFile], or null when the user backs out.
///
/// The file is already upright, and mirrored when the front lens took it, so
/// the caller can hand it straight to `inspectChatMediaFiles`.
class ChatCameraScreen extends StatefulWidget {
  const ChatCameraScreen({super.key, @visibleForTesting this.normalizeCapture});

  /// Overridden by tests only. The real one spawns an isolate, which never
  /// runs under a widget test's fake clock.
  final Future<bool> Function(String path, {required bool mirror})?
  normalizeCapture;

  @override
  State<ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<ChatCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  _Stage _stage = _Stage.loading;
  _Failure? _failure;
  bool _flashSupported = false;
  bool _lockCaptureToPortrait = true;

  /// Bumped whenever the current controller is abandoned. Async work started
  /// under an older generation checks this and drops its result instead of
  /// installing a controller the screen has already moved on from.
  int _generation = 0;

  /// True while [_bootstrap] is in flight, so a resume does not start a second
  /// one alongside it.
  bool _bootstrapping = false;

  /// Set when the app is backgrounded while a controller is still being
  /// built, so the resume rebuilds it.
  ///
  /// The camera cannot simply be released at that moment: iOS holds the app
  /// inactive while its own permission alert is up, and cancelling the
  /// in-flight start there would strand the screen on its placeholder with
  /// nothing left to finish the job.
  bool _restartOnResume = false;

  /// The last teardown, awaited before a controller is created: iOS keeps
  /// exactly one camera, and creating the next one before the previous has
  /// finished closing tears down the new one instead.
  Future<void>? _teardown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Phones run portrait-only (iOS `Info.plist`, Android manifest) but the
    // plugin follows the *physical* device orientation, so a tilted phone
    // would get a reshaped viewfinder and a rotated capture. An iPad really
    // does rotate, so it is left alone.
    _lockCaptureToPortrait = MediaQuery.sizeOf(context).shortestSide < 600;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) _recordTeardown(controller);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A preview resumed over a disposed controller is a black rectangle, so
      // the controller is rebuilt rather than reused. A denied permission is
      // worth retrying too: the user may have just switched it on in Settings.
      final retryAfterDenial =
          _stage != _Stage.failed || _failure == _Failure.denied;
      if (_restartOnResume) {
        // A controller built while the app was away may be attached to a
        // session the OS already interrupted, so it is replaced rather than
        // trusted. _bootstrap invalidates whatever is still in flight.
        _restartOnResume = false;
        _releaseController();
        unawaited(_bootstrap());
      } else if (_controller == null && !_bootstrapping && retryAfterDenial) {
        unawaited(_bootstrap());
      }
      return;
    }
    // Never tear the camera down mid-capture: on iOS that is what loses the
    // reply and hangs the capture future.
    if (_stage == _Stage.capturing || _stage == _Stage.processing) return;
    if (_controller == null && _bootstrapping) _restartOnResume = true;
    // Otherwise hand the camera back to the OS. This no-ops while iOS's own
    // permission alert holds the app inactive, because there is no controller
    // yet at that point — only a bootstrap in flight.
    _releaseController();
  }

  Future<void> _bootstrap() async {
    final generation = ++_generation;
    _bootstrapping = true;
    if (mounted && _stage != _Stage.loading) {
      setState(() {
        _stage = _Stage.loading;
        _failure = null;
      });
    }
    try {
      final List<CameraDescription> cameras;
      try {
        // This neither prompts nor throws for permissions; it returns an empty
        // list on a device without cameras, such as the iOS Simulator.
        cameras = await availableCameras();
      } catch (_) {
        _fail(_Failure.unavailable, generation);
        return;
      }
      if (!mounted || generation != _generation) return;
      _cameras = cameras;
      final description =
          cameras.firstWhereOrNull((c) => c.lensDirection == _lastLens) ??
          cameras.firstOrNull;
      if (description == null) {
        _fail(_Failure.unavailable, generation);
        return;
      }
      await _start(description, generation);
    } finally {
      _bootstrapping = false;
    }
  }

  Future<void> _start(CameraDescription description, int generation) async {
    // Let the previous camera finish closing before opening the next one.
    await _teardown;
    if (!mounted || generation != _generation) return;

    final controller = CameraController(
      description,
      // Stands in for the picker's old `maxWidth/maxHeight: 2048,
      // imageQuality: 88`, which the camera plugin has no knobs for. 1080p
      // also keeps a capture well under the chat media size cap.
      ResolutionPreset.veryHigh,
      // Mandatory: audio would make the plugin request a microphone
      // permission, and Info.plist carries no purpose string for one.
      enableAudio: false,
    );
    var flashSupported = false;
    try {
      // The permission prompt happens here, not in `availableCameras`.
      await controller.initialize();
      if (_lockCaptureToPortrait) {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      }
      try {
        // Apply the user's choice to both lenses, including the front camera's
        // screen flash, instead of leaving the platform's auto-flash default.
        // Setting a mode on a lens with no flash may throw.
        await controller.setFlashMode(_lastFlashMode);
        flashSupported = true;
      } on CameraException {
        flashSupported = false;
      }
    } on CameraException catch (error) {
      _recordTeardown(controller);
      _fail(_failureFor(error.code), generation);
      return;
    } catch (_) {
      _recordTeardown(controller);
      _fail(_Failure.unavailable, generation);
      return;
    }
    if (!mounted || generation != _generation) {
      // Abandoned mid-initialization. Recording the close keeps the next
      // controller from opening alongside this one, which on iOS would tear
      // the new one down instead.
      _recordTeardown(controller);
      return;
    }
    setState(() {
      _controller = controller;
      _flashSupported = flashSupported;
      _lastLens = description.lensDirection;
      _stage = _Stage.ready;
      _failure = null;
    });
  }

  /// Remembers a controller that is closing, so the next one waits for it.
  ///
  /// Failures are swallowed here rather than left to surface from
  /// `await _teardown` on a path that has nowhere to report them.
  void _recordTeardown(CameraController controller) {
    final closing = controller.dispose().catchError((Object _) {});
    final pending = _teardown;
    _teardown = pending == null ? closing : pending.then((_) => closing);
  }

  /// Abandons the current controller without waiting for it to close.
  void _releaseController() {
    final controller = _controller;
    if (controller == null) return;
    _generation++;
    if (mounted) {
      setState(() {
        _controller = null;
        if (_stage != _Stage.failed) _stage = _Stage.loading;
      });
    } else {
      _controller = null;
    }
    _recordTeardown(controller);
  }

  void _fail(_Failure failure, int generation) {
    if (!mounted || generation != _generation) return;
    setState(() {
      _controller = null;
      _stage = _Stage.failed;
      _failure = failure;
    });
  }

  static _Failure _failureFor(String code) => switch (code) {
    // Both platforms use these for a refusal; only iOS distinguishes the
    // "already denied, no prompt shown" case, and both are fixable in Settings.
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' => _Failure.denied,
    'CameraAccessRestricted' => _Failure.restricted,
    _ => _Failure.unavailable,
  };

  Future<void> _capture() async {
    final controller = _controller;
    if (_stage != _Stage.ready || controller == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _stage = _Stage.capturing);

    final XFile shot;
    try {
      shot = await controller.takePicture().timeout(_captureTimeout);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _stage = _Stage.ready);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.cameraCaptureFailed)));
      if (error is TimeoutException) {
        // The camera is not answering; a fresh controller is the only way back.
        _releaseController();
        unawaited(_bootstrap());
      }
      return;
    }
    if (!mounted) return;
    // A scrim covers the still-live preview while the bake runs. The preview
    // is deliberately not swapped for the file: `Image.file` caches by path,
    // and the bake rewrites that path, so a pre-bake render would leave the
    // send screen showing stale, unmirrored pixels.
    setState(() => _stage = _Stage.processing);

    final normalize = widget.normalizeCapture ?? normalizeCaptureFile;
    await normalize(
      shot.path,
      mirror: controller.description.lensDirection == CameraLensDirection.front,
    );
    if (!mounted) return;
    Navigator.of(context).pop(shot);
  }

  Future<void> _flipLens() async {
    final current = _controller?.description.lensDirection;
    if (_stage != _Stage.ready || _cameras.length < 2 || current == null) {
      return;
    }
    final next = _cameras.firstWhereOrNull((c) => c.lensDirection != current);
    if (next == null) return;
    HapticFeedback.selectionClick();
    _releaseController();
    await _start(next, _generation);
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || _stage != _Stage.ready) return;
    final next = switch (_lastFlashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
    } on CameraException {
      if (!mounted) return;
      setState(() => _flashSupported = false);
      return;
    }
    if (!mounted) return;
    setState(() => _lastFlashMode = next);
  }

  Future<void> _openSettings() async {
    try {
      await ph.openAppSettings();
    } catch (_) {
      // Nothing to do: the message already tells the user where to look.
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _stage == _Stage.capturing || _stage == _Stage.processing;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        // Blocks the back gesture mid-capture. A programmatic pop still works,
        // which is how a finished capture leaves.
        canPop: !busy,
        child: Scaffold(
          key: const ValueKey('chat-camera-screen'),
          backgroundColor: const Color(0xFF090708),
          body: Stack(
            fit: StackFit.expand,
            children: [
              _buildViewfinder(busy: busy),
              if (_stage != _Stage.failed) ...[
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _buildTopBar(busy: busy),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildBottomBar(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewfinder({required bool busy}) {
    if (_stage == _Stage.failed) {
      return _ChatCameraError(
        key: const ValueKey('chat-camera-error'),
        failure: _failure ?? _Failure.unavailable,
        onOpenSettings: _openSettings,
        onCancel: () => Navigator.of(context).pop(),
      );
    }
    final controller = _controller;
    if (controller == null) {
      // Static on purpose: an indeterminate progress indicator animates
      // forever, which makes `pumpAndSettle` in a widget test time out.
      return const ColoredBox(
        key: ValueKey('chat-camera-loading'),
        color: Color(0xFF090708),
        child: Center(
          child: Icon(
            Icons.photo_camera_outlined,
            color: Colors.white24,
            size: 44,
          ),
        ),
      );
    }
    // Letterboxed rather than cropped to fill: the sent frame has to be the
    // frame the user saw, which is the whole point of this screen.
    Widget preview = CameraPreview(controller);
    if (!_pluginMirrorsFrontPreview &&
        controller.description.lensDirection == CameraLensDirection.front) {
      preview = Transform.flip(flipX: true, child: preview);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: KeyedSubtree(
            key: const ValueKey('chat-camera-preview'),
            child: preview,
          ),
        ),
        if (busy)
          const ColoredBox(
            key: ValueKey('chat-camera-processing'),
            color: Color(0xE6090708),
            child: Center(
              child: Icon(
                Icons.photo_camera_rounded,
                color: Colors.white70,
                size: 40,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar({required bool busy}) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('chat-camera-close'),
            tooltip: S.cancel,
            // Inert during a capture, to match PopScope above. A pop here
            // while the bake is running would leave _capture to pop a second
            // route once it finished — the chat thread itself.
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          const Spacer(),
          if (_flashSupported)
            IconButton(
              key: const ValueKey('chat-camera-flash'),
              tooltip: switch (_lastFlashMode) {
                FlashMode.auto => S.flashAuto,
                FlashMode.off => S.flashOff,
                _ => S.flashOn,
              },
              onPressed: _stage == _Stage.ready ? _cycleFlash : null,
              icon: Icon(switch (_lastFlashMode) {
                FlashMode.auto => Icons.flash_auto_rounded,
                FlashMode.off => Icons.flash_off_rounded,
                _ => Icons.flash_on_rounded,
              }, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final ready = _stage == _Stage.ready;
    return Padding(
      // Sits above the safe-area inset, so the gap is comfortable on a phone
      // with a home indicator and still clear of the edge on one without.
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      // The explicit height is load-bearing. `Center` below has no height
      // factor, so under the loose vertical constraint an Align hands down it
      // grows to the full screen, taking the row with it and stranding the
      // shutter in the middle of the display instead of above the bottom edge.
      child: SizedBox(
        height: _shutterDiameter,
        child: Row(
          children: [
            // Balances the flip button so the shutter sits centred.
            const SizedBox(width: 48),
            Expanded(
              child: Center(
                child: Semantics(
                  button: true,
                  label: S.takePhoto,
                  child: _Shutter(
                    key: const ValueKey('chat-camera-shutter'),
                    onTap: ready ? _capture : null,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: IconButton(
                key: const ValueKey('chat-camera-flip'),
                tooltip: S.switchCamera,
                onPressed: ready && _cameras.length > 1 ? _flipLens : null,
                icon: const Icon(
                  Icons.cameraswitch_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shutter: a white ring around a white disc, dimmed when it is not armed.
class _Shutter extends StatelessWidget {
  const _Shutter({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: _shutterDiameter,
            height: _shutterDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of a viewfinder when the camera will not start.
class _ChatCameraError extends StatelessWidget {
  const _ChatCameraError({
    super.key,
    required this.failure,
    required this.onOpenSettings,
    required this.onCancel,
  });

  final _Failure failure;
  final VoidCallback onOpenSettings;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final denied = failure == _Failure.denied;
    final title = denied ? S.cameraPermissionTitle : S.cameraUnavailable;
    final body = switch (failure) {
      _Failure.denied => S.cameraPermissionBody,
      _Failure.restricted => S.cameraRestrictedBody,
      _Failure.unavailable => S.cameraUnavailableBody,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white38,
            size: 48,
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),
          if (denied)
            FilledButton(
              key: const ValueKey('chat-camera-open-settings'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
              ),
              onPressed: onOpenSettings,
              child: Text(S.openSettings),
            ),
          TextButton(
            key: const ValueKey('chat-camera-error-cancel'),
            onPressed: onCancel,
            child: Text(
              S.cancel,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

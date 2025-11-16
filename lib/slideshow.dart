import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullScreenSlideshow extends StatefulWidget {
  const FullScreenSlideshow({
    super.key,
    required this.imagePaths,
    this.interval = const Duration(seconds: 3),
    this.popToAlbumsListOnBack = false,
    this.popBackDepth = 1,
    this.slideDuration = const Duration(milliseconds: 450),
  });

  final List<String> imagePaths;
  final Duration interval;
  final bool popToAlbumsListOnBack;
  // How many pages to pop when handling system back. 1 = just close slideshow.
  // If opened from AlbumDetail but want to return to Albums list, set to 2.
  final int popBackDepth;
  final Duration slideDuration;

  @override
  State<FullScreenSlideshow> createState() => _FullScreenSlideshowState();
}

class _FullScreenSlideshowState extends State<FullScreenSlideshow> {
  late final PageController _controller;
  Timer? _timer;
  int _currentIndex = 0;
  bool _isPlaying = true;
  bool _zoomPaused = false;
  final Map<int, TransformationController> _transformControllers = {};
  static const double _scaleEpsilon = 0.05;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _enterImmersiveMode();
    _startTimer();
  }

  void _enterImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_isPlaying || _zoomPaused || widget.imagePaths.length < 2) {
      return;
    }
    _timer = Timer.periodic(widget.interval, (_) => _nextImage());
  }

  void _nextImage() {
    if (!_controller.hasClients) return;
    final total = widget.imagePaths.length;
    final nextIndex = (_currentIndex + 1) % total;
    _controller.animateToPage(
      nextIndex,
      duration: widget.slideDuration,
      curve: Curves.easeInOut,
    );
  }

  void _togglePlay() {
    setState(() => _isPlaying = !_isPlaying);
    _isPlaying ? _startTimer() : _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _restoreSystemUi();
    super.dispose();
  }

  double _currentScale(TransformationController c) {
    final m = c.value;
    // Approximate scale on X axis
    return m.storage[0];
  }

  void _setZoomPaused(bool paused) {
    if (_zoomPaused == paused) return;
    setState(() {
      _zoomPaused = paused;
    });
    if (_zoomPaused) {
      _timer?.cancel();
    } else {
      _startTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.popToAlbumsListOnBack,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (widget.popToAlbumsListOnBack) {
          int remaining = widget.popBackDepth.clamp(1, 5);
          final nav = Navigator.of(context);
          while (remaining > 0 && nav.canPop()) {
            nav.pop();
            remaining -= 1;
          }
          if (remaining > 0) {
            // Fallback to root navigator if nested navigator exhausted
            final rootNav = Navigator.of(context, rootNavigator: true);
            while (remaining > 0 && rootNav.canPop()) {
              rootNav.pop();
              remaining -= 1;
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MediaQuery.removeViewPadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlay,
            child: PageView.builder(
              physics: _zoomPaused
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
                controller: _controller,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                  if (_isPlaying) {
                    _startTimer();
                  }
                },
                itemCount: widget.imagePaths.length,
                itemBuilder: (context, index) {
                  final path = widget.imagePaths[index];
                  final tc = _transformControllers[index] ??=
                      TransformationController();
                  return _InteractiveFullScreenImage(
                    path: path,
                    controller: tc,
                    onInteractionStart: () {
                      _setZoomPaused(true);
                    },
                    onScaleChanged: (scale) {
                      // Pause when scale != 1, resume when back to 1 (epsilon)
                      if ((scale - 1.0).abs() > _scaleEpsilon) {
                        _setZoomPaused(true);
                      } else {
                        _setZoomPaused(false);
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InteractiveFullScreenImage extends StatefulWidget {
  const _InteractiveFullScreenImage({
    required this.path,
    required this.controller,
    required this.onScaleChanged,
    this.onInteractionStart,
  });

  final String path;
  final TransformationController controller;
  final void Function(double scale) onScaleChanged;
  final VoidCallback? onInteractionStart;

  @override
  State<_InteractiveFullScreenImage> createState() =>
      _InteractiveFullScreenImageState();
}

class _InteractiveFullScreenImageState
    extends State<_InteractiveFullScreenImage> with TickerProviderStateMixin {
  AnimationController? _anim;
  Animation<Matrix4>? _matrixAnim;

  @override
  void dispose() {
    _anim?.dispose();
    _anim = null;
    super.dispose();
  }

  void _animateToMatrix(Matrix4 target) {
    if (_anim != null) {
      _anim!.stop();
      _anim!.dispose();
      _anim = null;
    }
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _matrixAnim = Matrix4Tween(
      begin: widget.controller.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: _anim!, curve: Curves.easeInOut));
    _anim!.addListener(() {
      widget.controller.value = _matrixAnim!.value;
      widget.onScaleChanged(widget.controller.value.storage[0]);
    });
    _anim!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        // leave controller for reuse; do not auto-dispose here
      }
    });
    _anim!.forward();
  }
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: GestureDetector(
          onDoubleTap: () {
            final current = widget.controller.value.storage[0];
            final targetScale =
                (current - 1.0).abs() < _FullScreenSlideshowState._scaleEpsilon
                    ? 2.0
                    : 1.0;
            // Centered zoom: T(center) * S(scale) * T(-center)
            final size = context.size;
            if (size != null) {
              final cx = size.width / 2;
              final cy = size.height / 2;
              final target = Matrix4.identity()
                ..translate(cx, cy)
                ..scale(targetScale)
                ..translate(-cx, -cy);
              _animateToMatrix(target);
            } else {
              widget.controller.value = Matrix4.identity()..scale(targetScale);
              widget.onScaleChanged(targetScale);
            }
          },
          child: InteractiveViewer
          (
            transformationController: widget.controller,
            minScale: 1.0,
            maxScale: 5.0,
            panEnabled: true,
            onInteractionStart: (_) {
              widget.onInteractionStart?.call();
            },
            onInteractionUpdate: (_) {
              widget.onScaleChanged(widget.controller.value.storage[0]);
            },
            onInteractionEnd: (_) {
              widget.onScaleChanged(widget.controller.value.storage[0]);
            },
            child: FittedBox(
              fit: BoxFit.cover,
              child: Image.file(
                File(widget.path),
                errorBuilder: (context, error, stackTrace) => const Text(
                  '无法显示该图片',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        )
      ),
    );
  }
}




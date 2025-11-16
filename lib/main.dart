import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const ImageViewApp());
}

class ImageViewApp extends StatelessWidget {
  const ImageViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '本地图片幻灯片',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
      ),
      home: const ImageLoaderPage(),
    );
  }
}

class ImageLoaderPage extends StatefulWidget {
  const ImageLoaderPage({super.key});

  @override
  State<ImageLoaderPage> createState() => _ImageLoaderPageState();
}

class _ImageLoaderPageState extends State<ImageLoaderPage> {
  bool _isPicking = false;
  String? _error;

  Future<bool> _ensurePermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }

    if (Platform.isAndroid) {
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted || photosStatus.isLimited) {
        return true;
      }

      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) {
        return true;
      }

      if (photosStatus.isPermanentlyDenied ||
          storageStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return false;
    }

    return true;
  }

  Future<void> _pickImages() async {
    if (_isPicking) return;
    setState(() => _error = null);

    final granted = await _ensurePermission();
    if (!granted) {
      setState(() {
        _error = '需要访问照片的权限，请在系统设置中授权后重试。';
      });
      return;
    }

    setState(() => _isPicking = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        allowCompression: false,
      );

      if (!mounted) return;

      final paths = result?.paths.whereType<String>().toList() ?? [];
      if (paths.isEmpty) {
        setState(() => _error = '未选择任何图片或无法读取路径。');
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullScreenSlideshow(imagePaths: paths),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = '选择图片时出错：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地图片幻灯片'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '功能说明',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('• 读取本地图片并进入全屏播放。'),
            const Text('• 图片全屏展示，屏幕上不会覆盖控件。'),
            const Text('• 幻灯片模式自动轮播，轻触屏幕可暂停/继续。'),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: _isPicking ? null : _pickImages,
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_isPicking ? '读取中...' : '选择本地图片'),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const Spacer(),
            Text(
              '提示：进入全屏后轻触屏幕即可暂停或恢复自动播放，使用系统返回手势退出。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class FullScreenSlideshow extends StatefulWidget {
  const FullScreenSlideshow({
    super.key,
    required this.imagePaths,
    this.interval = const Duration(seconds: 3),
  });

  final List<String> imagePaths;
  final Duration interval;

  @override
  State<FullScreenSlideshow> createState() => _FullScreenSlideshowState();
}

class _FullScreenSlideshowState extends State<FullScreenSlideshow> {
  late final PageController _controller;
  Timer? _timer;
  int _currentIndex = 0;
  bool _isPlaying = true;

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
    if (!_isPlaying || widget.imagePaths.length < 2) {
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
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  void _togglePlay() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                return _FullScreenImage(path: path);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: Image.file(
            File(path),
            errorBuilder: (context, error, stackTrace) => const Text(
              '无法显示该图片',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

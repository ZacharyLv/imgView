import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'albums_page.dart' as albums;
import 'slideshow.dart';

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
      home: const _HomeRouter(),
    );
  }
}

class _HomeRouter extends StatelessWidget {
  const _HomeRouter();

  @override
  Widget build(BuildContext context) {
    return const AlbumsEntry();
  }
}

class AlbumsEntry extends StatelessWidget {
  const AlbumsEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return const AlbumsScaffold();
  }
}

class AlbumsScaffold extends StatelessWidget {
  const AlbumsScaffold({super.key});
  static final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // Lazy import to avoid circular deps at compile time
    return PopScope(
      canPop: false, // never exit app via system back from this root
      onPopInvoked: (didPop) {
        if (didPop) return;
        final nav = _navKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else {
          // We are on the albums list (root). Exit to home screen.
          SystemNavigator.pop();
        }
      },
      child: Navigator(
        key: _navKey,
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (_) {
              // ignore: avoid_print
              print('Loading AlbumsPage...');
              // Import here
              return _AlbumsHost();
            },
          );
        },
      ),
    );
  }
}

class _AlbumsHost extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // This indirection allows keeping slideshow types in this file
    // while AlbumsPage resides in a separate file.
    return const _AlbumsPageProxy();
  }
}

// A small proxy widget to keep imports one-way
class _AlbumsPageProxy extends StatelessWidget {
  const _AlbumsPageProxy();

  @override
  Widget build(BuildContext context) {
    // ignore: avoid_relative_lib_imports
    // ignore_for_file: implementation_imports
    // Proper import:
    return _AlbumsReal();
  }
}

class _AlbumsReal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const albums.AlbumsPage();
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

// Slideshow widget moved to slideshow.dart

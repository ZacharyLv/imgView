import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'slideshow.dart';
import 'storage.dart';

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    super.key,
    required this.albumName,
    this.autoStartOnFirstAdd = false,
  });

  final String albumName;
  final bool autoStartOnFirstAdd;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final _storage = AlbumStorage.instance;
  List<File> _files = const [];
  bool _loading = true;
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    () async {
      setState(() {
        _loading = true;
        _selected.clear();
        _selectionMode = false;
      });
      final files = await _storage.listImages(widget.albumName);
      if (!mounted) return;
      setState(() {
        // Keep storage order (lastModified desc => newest first)
        _files = files;
        _loading = false;
      });
    }();
  }

  Future<void> _addImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        allowCompression: false,
      );
      final paths = result?.paths.whereType<String>().toList() ?? [];
      if (paths.isEmpty) return;
      final newFiles = <File>[];
      for (final p in paths) {
        final copied = await _storage.addImageToAlbum(
          album: widget.albumName,
          sourceFile: File(p),
        );
        newFiles.add(copied);
      }
      // Persist their relative order at the very front (in selection order)
      await _storage.prependImagesToOrder(widget.albumName, newFiles);
      // Prepend newly added images to the beginning of the displayed list
      // while keeping existing order for the rest. Deduplicate by path.
      final existing = <String, File>{
        for (final f in _files) f.path: f,
      };
      for (final f in newFiles) {
        existing.remove(f.path); // ensure no duplicates when we prepend
      }
      if (!mounted) return;
      setState(() {
        _files = <File>[...newFiles, ...existing.values];
        _selected.clear();
        _selectionMode = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加图片失败：$e')),
      );
    }
  }

  Future<void> _deleteImage(File file) async {
    await _storage.deleteImage(file);
    if (!mounted) return;
    setState(() {
      _files = _files.where((f) => f.path != file.path).toList(growable: false);
      _selected.remove(file.path);
      _selectionMode = _selected.isNotEmpty;
    });
  }

  Future<void> _deleteSelected(List<File> files) async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除选中图片'),
        content: Text('确定删除选中的 ${_selected.length} 张图片吗？该操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final f in files) {
      if (_selected.contains(f.path)) {
        await _storage.deleteImage(f);
      }
    }
    if (!mounted) return;
    setState(() {
      _files =
          _files.where((f) => !_selected.contains(f.path)).toList(growable: false);
      _selected.clear();
      _selectionMode = false;
    });
  }

  void _openSlideshow(List<File> files, int startIndex) {
    if (files.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenSlideshow(
          imagePaths: files.map((f) => f.path).toList(),
          popToAlbumsListOnBack: true,
          popBackDepth: 2, // from detail -> back pops slideshow + detail
        ),
      ),
    );
  }

  void _openSingleAt(int startIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SingleImagePager(
          files: _files,
          initialIndex: startIndex,
        ),
      ),
    );
  }

  Future<void> _playAll() async {
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('相册暂无图片')),
      );
      return;
    }
    final shuffle = await _storage.getAlbumShuffle(widget.albumName);
    final speedX = await _storage.getAlbumSpeedX(widget.albumName);
    Duration slideDuration;
    switch (speedX) {
      case 'x1':
        slideDuration = const Duration(milliseconds: 450);
        break;
      case 'x3':
        slideDuration = const Duration(milliseconds: 1500);
        break;
      case 'x2':
      default:
        slideDuration = const Duration(milliseconds: 975);
    }
    final paths = _files.map((f) => f.path).toList();
    if (shuffle) {
      paths.shuffle();
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenSlideshow(
          imagePaths: paths,
          popToAlbumsListOnBack: true,
          popBackDepth: 2,
          slideDuration: slideDuration,
        ),
      ),
    );
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
      _selectionMode = _selected.isNotEmpty;
    });
  }

  void _selectAll(List<File> files) {
    setState(() {
      _selected
        ..clear()
        ..addAll(files.map((e) => e.path));
      _selectionMode = _selected.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode
            ? '已选择 ${_selected.length} 项'
            : widget.albumName),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
                tooltip: '退出多选',
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            IconButton(
              onPressed: () async {
                await _deleteSelected(_files);
              },
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除所选',
            ),
          ] else ...[
            IconButton(
              onPressed: _playAll,
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: '自动预览',
            ),
            IconButton(
              onPressed: _addImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: '添加图片',
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('相册暂无图片'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _addImages,
                        child: const Text('添加图片'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final selected = _selected.contains(file.path);
                    return Container(
                      key: ValueKey(file.path),
                      child: GestureDetector(
                      onTap: () {
                        if (_selectionMode) {
                          _toggleSelect(file.path);
                        } else {
                          _openSingleAt(index);
                        }
                      },
                      onLongPress: () {
                        if (!_selectionMode) {
                          _toggleSelect(file.path);
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            file,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(
                              color: Colors.black12,
                              child: Center(
                                  child: Icon(Icons.broken_image_outlined)),
                            ),
                          ),
                          if (_selectionMode)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.black26
                                    : Colors.transparent,
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: selected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    );
                  },
                )),
    );
  }
}

class _SingleImagePage extends StatefulWidget {
  const _SingleImagePage({required this.imageFile});

  final File imageFile;

  @override
  State<_SingleImagePage> createState() => _SingleImagePageState();
}

class _SingleImagePageState extends State<_SingleImagePage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
          child: ColoredBox(
            color: Colors.black,
            child: SizedBox.expand(
              child: _DoubleTapZoomViewer(imageFile: widget.imageFile),
            ),
          ),
        ),
      ),
    );
  }
}

class _SingleImagePager extends StatefulWidget {
  const _SingleImagePager({required this.files, required this.initialIndex});

  final List<File> files;
  final int initialIndex;

  @override
  State<_SingleImagePager> createState() => _SingleImagePagerState();
}

class _SingleImagePagerState extends State<_SingleImagePager> {
  late final PageController _pageController;
  final Map<int, TransformationController> _controllers = {};
  bool _zoomPaused = false;

  static const double _eps = 0.05;
  late final int _loopOffset;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Large offset to emulate circular paging
    _loopOffset = (widget.files.length * 1000);
    _pageController = PageController(initialPage: _loopOffset + widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _handleScaleChanged(double scale) {
    final paused = (scale - 1.0).abs() > _eps;
    if (paused != _zoomPaused) {
      setState(() => _zoomPaused = paused);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removeViewPadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: ColoredBox(
          color: Colors.black,
          child: PageView.builder(
            physics:
                _zoomPaused ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            controller: _pageController,
            // infinite builder; map to cyclic index
            itemBuilder: (context, index) {
              final cyc = index % widget.files.length;
              final file = widget.files[cyc];
              final tc = _controllers[cyc] ??= TransformationController();
              return _PagerZoomImage(
                file: file,
                controller: tc,
                onScaleChanged: _handleScaleChanged,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PagerZoomImage extends StatefulWidget {
  const _PagerZoomImage({
    required this.file,
    required this.controller,
    required this.onScaleChanged,
  });

  final File file;
  final TransformationController controller;
  final void Function(double scale) onScaleChanged;

  @override
  State<_PagerZoomImage> createState() => _PagerZoomImageState();
}

class _PagerZoomImageState extends State<_PagerZoomImage>
    with TickerProviderStateMixin {
  AnimationController? _anim;
  Animation<Matrix4>? _matrixAnim;

  @override
  void dispose() {
    _anim?.dispose();
    _anim = null;
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    if (_anim != null) {
      _anim!.stop();
      _anim!.dispose();
      _anim = null;
    }
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _matrixAnim = Matrix4Tween(
      begin: widget.controller.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: _anim!, curve: Curves.easeInOut));
    _anim!.addListener(() {
      widget.controller.value = _matrixAnim!.value;
      widget.onScaleChanged(widget.controller.value.storage[0]);
    });
    _anim!.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        final current = widget.controller.value.storage[0];
        final targetScale = (current - 1.0).abs() < 0.05 ? 2.0 : 1.0;
        final size = context.size;
        if (size != null) {
          final cx = size.width / 2;
          final cy = size.height / 2;
          final target = Matrix4.identity()
            ..translate(cx, cy)
            ..scale(targetScale)
            ..translate(-cx, -cy);
          _animateTo(target);
        } else {
          widget.controller.value = Matrix4.identity()..scale(targetScale);
          widget.onScaleChanged(targetScale);
        }
      },
      child: InteractiveViewer(
        transformationController: widget.controller,
        minScale: 1.0,
        maxScale: 5.0,
        panEnabled: true,
        onInteractionUpdate: (_) =>
            widget.onScaleChanged(widget.controller.value.storage[0]),
        onInteractionEnd: (_) =>
            widget.onScaleChanged(widget.controller.value.storage[0]),
        child: FittedBox(
          fit: BoxFit.cover,
          child: Image.file(
            widget.file,
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

class _DoubleTapZoomViewer extends StatefulWidget {
  const _DoubleTapZoomViewer({required this.imageFile});

  final File imageFile;

  @override
  State<_DoubleTapZoomViewer> createState() => _DoubleTapZoomViewerState();
}

class _DoubleTapZoomViewerState extends State<_DoubleTapZoomViewer>
    with TickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  AnimationController? _anim;
  Animation<Matrix4>? _matrixAnim;

  @override
  void dispose() {
    _anim?.dispose();
    _anim = null;
    _tc.dispose();
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
      begin: _tc.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: _anim!, curve: Curves.easeInOut));
    _anim!.addListener(() {
      _tc.value = _matrixAnim!.value;
    });
    _anim!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        // keep controller for reuse; not disposing here
      }
    });
    _anim!.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        final current = _tc.value.storage[0];
        final targetScale = (current - 1.0).abs() < 0.01 ? 2.0 : 1.0;
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
          setState(() {
            _tc.value = Matrix4.identity()..scale(targetScale);
          });
        }
      },
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1.0,
        maxScale: 5.0,
        panEnabled: true,
        child: FittedBox(
          fit: BoxFit.cover,
          child: Image.file(
            widget.imageFile,
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



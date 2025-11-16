import 'package:flutter/material.dart';

import 'album_detail_page.dart';
import 'slideshow.dart';
import 'storage.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  final _storage = AlbumStorage.instance;
  List<String> _albums = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _storage.listAlbums();
    if (!mounted) return;
    setState(() {
      _albums = list;
      _loading = false;
    });
  }

  Future<void> _createAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新建相册'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入相册名称',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  Navigator.pop(context, text);
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    if (name == null) return;
    await _storage.createAlbum(name);
    await _load();
    if (!mounted) return;
    // After creating, jump in and auto start slideshow after first add
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailPage(
          albumName: name,
        ),
      ),
    );
    await _load();
  }

  Future<void> _deleteAlbum(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除相册'),
        content: Text('确定删除相册“$name”及其中的所有图片吗？该操作不可恢复。'),
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
    await _storage.deleteAlbum(name);
    await _load();
  }

  Future<void> _renameAlbum(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名相册'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '输入新的相册名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty && text != oldName) {
                  Navigator.pop(context, text);
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (newName == null) return;
    try {
      await _storage.renameAlbum(from: oldName, to: newName);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('重命名失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        actions: [
          IconButton(
            onPressed: _createAlbum,
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建相册',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_albums.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('还没有相册'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _createAlbum,
                        child: const Text('新建相册'),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: _albums.length,
                  onReorder: (oldIndex, newIndex) async {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _albums.removeAt(oldIndex);
                      _albums.insert(newIndex, item);
                    });
                    await _storage.reorderAlbums(_albums);
                  },
                  itemBuilder: (context, index) {
                    final name = _albums[index];
                    return ListTile(
                      key: ValueKey('album-$name'),
                      contentPadding: const EdgeInsets.only(left: 16, right: 0),
                      title: Text(name),
                      leading: const Icon(Icons.folder_outlined),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded),
                            onPressed: () async {
                              final files =
                                  await _storage.listImages(name);
                              if (!mounted) return;
                              if (files.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('相册暂无图片')),
                                );
                                return;
                              }
                              final shuffle = await _storage.getAlbumShuffle(name);
                              final speedX = await _storage.getAlbumSpeedX(name);
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
                              List<String> paths = files.map((f) => f.path).toList();
                              if (shuffle) {
                                paths.shuffle();
                              }
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FullScreenSlideshow(
                                    imagePaths: paths,
                                    popToAlbumsListOnBack: true,
                                    popBackDepth: 1, // from list -> back pops slideshow only
                                    slideDuration: slideDuration,
                                  ),
                                ),
                              );
                            },
                            tooltip: '预览相册',
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _renameAlbum(name),
                            tooltip: '重命名',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteAlbum(name),
                            tooltip: '删除',
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: '播放设置',
                            onPressed: () async {
                              final currentShuffle = await _storage.getAlbumShuffle(name);
                              final currentSpeedX = await _storage.getAlbumSpeedX(name);
                              if (!mounted) return;
                              bool localShuffle = currentShuffle;
                              String speedX = currentSpeedX;
                              await showDialog<void>(
                                context: context,
                                builder: (context) {
                                  return StatefulBuilder(
                                    builder: (context, setLocalState) {
                                      return AlertDialog(
                                        title: Text('播放设置（$name）'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            RadioListTile<bool>(
                                              title: const Text('按顺序自动预览'),
                                              value: false,
                                              groupValue: localShuffle,
                                              onChanged: (v) => setLocalState(() => localShuffle = v ?? false),
                                            ),
                                            RadioListTile<bool>(
                                              title: const Text('随机顺序自动预览'),
                                              value: true,
                                              groupValue: localShuffle,
                                              onChanged: (v) => setLocalState(() => localShuffle = v ?? true),
                                            ),
                                            const SizedBox(height: 8),
                                            const Divider(),
                                            const ListTile(
                                              title: Text('切换速度'),
                                              dense: true,
                                            ),
                                            RadioListTile<String>(
                                              title: const Text('X1'),
                                              value: 'x1',
                                              groupValue: speedX,
                                              onChanged: (v) => setLocalState(() => speedX = v ?? 'x1'),
                                            ),
                                            RadioListTile<String>(
                                              title: const Text('X2'),
                                              value: 'x2',
                                              groupValue: speedX,
                                              onChanged: (v) => setLocalState(() => speedX = v ?? 'x2'),
                                            ),
                                            RadioListTile<String>(
                                              title: const Text('X3'),
                                              value: 'x3',
                                              groupValue: speedX,
                                              onChanged: (v) => setLocalState(() => speedX = v ?? 'x3'),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton(
                                            onPressed: () async {
                                              await _storage.setAlbumShuffle(name, localShuffle);
                                              await _storage.setAlbumSpeedX(name, speedX);
                                              if (mounted) Navigator.pop(context);
                                            },
                                            child: const Text('保存'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AlbumDetailPage(albumName: name),
                          ),
                        );
                        await _load();
                      },
                    );
                  },
                )),
    );
  }
}



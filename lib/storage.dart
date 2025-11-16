import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class AlbumStorage {
  AlbumStorage._();
  static final AlbumStorage instance = AlbumStorage._();

  Future<Directory> _getAlbumsRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory('${dir.path}/albums');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<File> _orderFile() async {
    final root = await _getAlbumsRoot();
    return File('${root.path}/.albums_order.json');
  }

  Future<File> _prefsFile() async {
    final root = await _getAlbumsRoot();
    return File('${root.path}/.albums_prefs.json');
  }

  Future<Map<String, dynamic>> _loadPrefs() async {
    try {
      final f = await _prefsFile();
      if (!await f.exists()) return <String, dynamic>{};
      final text = await f.readAsString();
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) return data;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _savePrefs(Map<String, dynamic> prefs) async {
    final f = await _prefsFile();
    await f.writeAsString(jsonEncode(prefs));
  }

  Future<File> _albumImagesOrderFile(String album) async {
    final path = await albumPath(album);
    return File('$path/.order.json');
  }

  Future<List<String>> _loadImageOrder(String album) async {
    try {
      final f = await _albumImagesOrderFile(album);
      if (!await f.exists()) return <String>[];
      final text = await f.readAsString();
      final data = jsonDecode(text);
      if (data is List) {
        return data.whereType<String>().toList();
      }
      return <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _saveImageOrder(String album, List<String> names) async {
    final f = await _albumImagesOrderFile(album);
    await f.writeAsString(jsonEncode(names));
  }

  Future<void> prependImagesToOrder(String album, List<File> filesInOrder) async {
    final current = await _loadImageOrder(album);
    final names = filesInOrder
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .toList();
    // Remove existing occurrences, preserve relative order of provided list
    final pruned = current.where((n) => !names.contains(n)).toList();
    final updated = <String>[...names, ...pruned];
    await _saveImageOrder(album, updated);
  }
  Future<List<String>> _loadSavedOrder() async {
    try {
      final f = await _orderFile();
      if (!await f.exists()) return const [];
      final text = await f.readAsString();
      final data = jsonDecode(text);
      if (data is List) {
        return data.whereType<String>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveOrder(List<String> names) async {
    final f = await _orderFile();
    await f.writeAsString(jsonEncode(names));
  }

  Future<List<String>> listAlbums() async {
    final root = await _getAlbumsRoot();
    final entities = await root.list(followLinks: false).toList();
    final names = <String>[];
    for (final e in entities) {
      if (e is Directory) {
        names.add(e.uri.pathSegments.isNotEmpty
            ? e.uri.pathSegments[e.uri.pathSegments.length - 2]
            : e.path.split(Platform.pathSeparator).last);
      }
    }
    // Apply saved order; append any new names at the end in alpha order
    final saved = await _loadSavedOrder();
    final set = names.toSet();
    final ordered = <String>[];
    for (final n in saved) {
      if (set.contains(n)) ordered.add(n);
    }
    final remaining = set.difference(ordered.toSet()).toList()..sort();
    ordered.addAll(remaining);
    return ordered;
  }

  Future<void> createAlbum(String name) async {
    final root = await _getAlbumsRoot();
    final dir = Directory('${root.path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Append to order
    final current = await listAlbums();
    if (!current.contains(name)) {
      current.add(name);
      await _saveOrder(current);
    }
  }

  Future<void> deleteAlbum(String name) async {
    final root = await _getAlbumsRoot();
    final dir = Directory('${root.path}/$name');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final current = await listAlbums();
    current.remove(name);
    await _saveOrder(current);
  }

  Future<void> renameAlbum({required String from, required String to}) async {
    final root = await _getAlbumsRoot();
    final fromDir = Directory('${root.path}/$from');
    final toDir = Directory('${root.path}/$to');
    if (!await fromDir.exists()) return;
    if (await toDir.exists()) {
      throw StateError('目标相册已存在');
    }
    await fromDir.rename(toDir.path);
    final current = await listAlbums();
    final idx = current.indexOf(from);
    if (idx >= 0) {
      current[idx] = to;
      await _saveOrder(current);
    }
  }

  Future<void> reorderAlbums(List<String> namesInOrder) async {
    // Ensure only existing albums are saved
    final actual = (await listAlbums()).toSet();
    final filtered = namesInOrder.where(actual.contains).toList();
    await _saveOrder(filtered);
  }

  Future<String> albumPath(String name) async {
    final root = await _getAlbumsRoot();
    return '${root.path}/$name';
  }

  Future<List<File>> listImages(String album) async {
    final dir = Directory(await albumPath(album));
    if (!await dir.exists()) return [];
    final files = <File>[];
    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is File) {
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png') ||
            lower.endsWith('.gif') ||
            lower.endsWith('.webp') ||
            lower.endsWith('.bmp') ||
            lower.endsWith('.heic') ||
            lower.endsWith('.heif')) {
          files.add(entity);
        }
      }
    }
    // Sort by last modified time desc (newest first). Fallback to path.
    final stats = await Future.wait(files.map((f) async {
      try {
        final dt = await f.lastModified();
        return MapEntry(f, dt);
      } catch (_) {
        return MapEntry(f, DateTime.fromMillisecondsSinceEpoch(0));
      }
    }));
    stats.sort((a, b) {
      final t = b.value.compareTo(a.value);
      if (t != 0) return t;
      return a.key.path.compareTo(b.key.path);
    });
    final sortedByTime = stats.map((e) => e.key).toList(growable: false);
    // Apply per-album image order preference (filenames), if present
    final order = await _loadImageOrder(album);
    if (order.isEmpty) return sortedByTime;
    final nameToFile = <String, File>{
      for (final f in sortedByTime) f.path.split(Platform.pathSeparator).last: f
    };
    final orderedFiles = <File>[];
    for (final name in order) {
      final f = nameToFile.remove(name);
      if (f != null) orderedFiles.add(f);
    }
    // Append remaining (not in order file), already sorted by time
    orderedFiles.addAll(nameToFile.values);
    return orderedFiles;
  }

  Future<bool> getAlbumShuffle(String album) async {
    final prefs = await _loadPrefs();
    final albumPrefs = prefs[album];
    if (albumPrefs is Map<String, dynamic>) {
      final v = albumPrefs['shuffle'];
      if (v is bool) return v;
    }
    return false;
  }

  Future<void> setAlbumShuffle(String album, bool shuffle) async {
    final prefs = await _loadPrefs();
    final current = (prefs[album] as Map<String, dynamic>?) ?? <String, dynamic>{};
    current['shuffle'] = shuffle;
    prefs[album] = current;
    await _savePrefs(prefs);
  }

  // Speed using x1/x2/x3 only

  // New API using x1/x2/x3 naming to avoid ambiguity
  Future<String> getAlbumSpeedX(String album) async {
    final prefs = await _loadPrefs();
    final albumPrefs = prefs[album];
    if (albumPrefs is Map<String, dynamic>) {
      final v = albumPrefs['speed'];
      if (v is String && (v == 'x1' || v == 'x2' || v == 'x3')) return v;
    }
    return 'x1'; // default to X1
  }

  Future<void> setAlbumSpeedX(String album, String speedX) async {
    if (speedX != 'x1' && speedX != 'x2' && speedX != 'x3') return;
    final prefs = await _loadPrefs();
    final current = (prefs[album] as Map<String, dynamic>?) ?? <String, dynamic>{};
    current['speed'] = speedX;
    prefs[album] = current;
    await _savePrefs(prefs);
  }

  Future<File> addImageToAlbum({
    required String album,
    required File sourceFile,
  }) async {
    final dirPath = await albumPath(album);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final fileName = _uniqueFileName(
      originalPath: sourceFile.path,
      targetDir: dirPath,
    );
    final dest = File('$dirPath/$fileName');
    return sourceFile.copy(dest.path);
  }

  Future<void> deleteImage(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
    // Remove from image order file if present
    try {
      final dir = file.parent;
      final album = dir.path.split(Platform.pathSeparator).last;
      final order = await _loadImageOrder(album);
      final name = file.path.split(Platform.pathSeparator).last;
      if (order.isNotEmpty && order.contains(name)) {
        order.removeWhere((e) => e == name);
        await _saveImageOrder(album, order);
      }
    } catch (_) {
      // ignore order cleanup errors
    }
  }

  String _uniqueFileName({
    required String originalPath,
    required String targetDir,
  }) {
    final originalName =
        originalPath.split(Platform.pathSeparator).last.replaceAll(' ', '_');
    final base = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : originalName;
    final ext = originalName.contains('.')
        ? originalName.substring(originalName.lastIndexOf('.'))
        : '';

    String candidate(int? idx) => idx == null ? '$base$ext' : '$base-$idx$ext';

    var index = 0;
    while (File('$targetDir/${candidate(index == 0 ? null : index)}')
        .existsSync()) {
      index += 1;
    }
    return candidate(index == 0 ? null : index);
  }
}



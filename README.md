# imgView

一个基于 Flutter 的跨平台图片查看应用。支持快速预览、缩放、滑动浏览与基础手势操作，适合作为图片浏览器或图像查看模块的起点工程。

## 功能特性
- 相册管理
  - 新建/删除相册，重命名相册
  - 相册拖拽排序（持久化保存顺序）
- 图片管理
  - 从系统相册选择图片后，复制到应用私有空间（Documents/albums/<相册名>/），即使系统相册删除原图，应用内仍可查看
  - 相册内图片多选删除（长按进入多选）
  - 新增图片总是插入到列表最前，且保持一次选择中的相对顺序；顺序通过 `.order.json` 持久化
- 展示与交互
  - 图片网格：最新在前（按文件最后修改时间降序；新增的批次靠前，批次内按选择顺序）
  - 单张预览（相册详情页点击进入）
    - 横向分页切换，支持“无限循环”左右滑动
    - 支持双指捏合缩放、拖拽；双击在 1x 与 2x 之间居中带动画切换
    - 放大时优先拖动当前图片，缩回≈1x 后才能左右切换
  - 自动预览（幻灯片）
    - 相册列表行的“播放”按钮或相册详情页右上角“自动预览”进入
    - 支持按顺序/随机；支持切换速度 X1/X2/X3（分别约 450ms/975ms/1500ms），每个相册可独立设置并持久化
    - 预览时单击可暂停/继续；捏合/双击放大暂停，缩回≈1x 自动恢复
- 返回行为
  - 预览/详情等次级页面：硬件返回回到上一级
  - 相册列表根页：硬件返回退出到桌面
- 跨平台：同一套代码多端运行
- 可扩展：便于集成本地相册、网络图片、缓存与占位图等能力

## 运行与开发
前置要求：已安装 Flutter SDK 与对应平台工具链。

```bash
# 获取依赖
flutter pub get

# 运行（选择其一）
flutter run -d macos
flutter run -d ios
flutter run -d android
flutter run -d chrome

# 格式化与静态检查
flutter format .
flutter analyze
```

## 构建发布
```bash
# Android（APK/AAB）
flutter build apk
flutter build appbundle

# iOS
flutter build ios

# Web
flutter build web

# macOS / Windows / Linux
flutter build macos
flutter build windows
flutter build linux
```

## 目录结构（节选）
- `lib/`
  - `main.dart`：应用入口与根导航拦截（根页返回退出、子页返回上一级）
  - `albums_page.dart`：相册列表（播放、重命名、删除、设置、拖拽排序）
  - `album_detail_page.dart`：相册详情（网格、添加、多选删除、单图分页预览）
  - `slideshow.dart`：全屏自动预览（手势与播放控制）
  - `storage.dart`：相册/图片本地存储、顺序与设置持久化（`albums/.albums_prefs.json`、每相册 `.order.json`）
- `android/`, `ios/`, `macos/`, `windows/`, `linux/`, `web/`：各平台工程

## 细节说明
- 权限
  - 仅在选择图片时申请必要权限；图片复制到应用私有目录后，后续浏览不再依赖系统相册权限
- 排序
  - 初次展示按文件最后修改时间降序（最新在前）
  - 新增图片的相对顺序按选择顺序写入 `.order.json` 并置于最前，后续进入维持一致
- 性能体验
  - 网格 cell 绑定稳定 Key，图片启用 `gaplessPlayback`，删除/新增就地更新，避免闪动

## 截图
（在此处放置实际运行截图）

## 许可
本项目默认遵循 MIT 协议。你可以按需修改为合适的开源许可证。

---
English (brief)

imgView is a Flutter-based, cross-platform image viewer supporting zoom, pan, and swipe gestures. It’s a solid starter for image browsing modules across Android, iOS, Web, macOS, Windows, and Linux.

Quick start:
```bash
flutter pub get
flutter run
```
Build:
```bash
flutter build <platform>
```

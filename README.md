<div align="center">

<image src="assets/icon/app_icon.png" width="128" height="128" />

# SecRandom Lite

[![GitHub Issues](https://img.shields.io/github/issues-search/SECTL/SecRandom-Lite?query=is%3Aopen&style=for-the-badge&color=66CCFF&logo=github&label=问题)](https://github.com/SECTL/SecRandom-Lite/issues)
[![最新版本](https://img.shields.io/github/v/release/SECTL/SecRandom-Lite?style=for-the-badge&color=66CCFF&label=最新版本)](https://github.com/SECTL/SecRandom-Lite/releases/latest)
[![上次更新](https://img.shields.io/github/last-commit/SECTL/SecRandom-Lite?style=for-the-badge&color=66CCFF&label=最后更新)](https://github.com/SECTL/SecRandom-Lite/commits/main)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](https://opensource.org/licenses/GPL-3.0)

[![QQ群](https://img.shields.io/badge/-QQ%E7%BE%A4%EF%BD%9C833875216-blue?style=for-the-badge&logo=QQ)](https://qm.qq.com/q/iWcfaPHn7W)
[![bilibili](https://img.shields.io/badge/-UP%E4%B8%BB%EF%BD%9C%E5%8F%B6%E8%83%8C%E5%BD%B1-%23FB7299?style=for-the-badge&logo=bilibili)](https://space.bilibili.com/1762621716)

</div>

--------

SecRandom Lite 是 [SecRandom](https://github.com/SECTL/SecRandom) 的轻量级 Flutter 版本。

- 继承了 SecRandom 的公平抽取等核心特性
- 支持运行在 Android、iOS、Windows、macOS、Linux 和 Web
- 采用 Material Design 3 设计规范
- 基于 Flutter ，启动快、占用少


### 支持平台

| 平台 | 最低版本 |
|------|----------|
| Android | Android 5.0 (API 21) |
| iOS | iOS 13.0 |
| Windows | Windows 10 |
| macOS | macOS 10.15 (Catalina) |
| Linux | Ubuntu 18.04+ |
| Web | 现代浏览器 |

## 下载/安装

### 下载

-  **[GitHub Releases](https://github.com/SECTL/SecRandom-Lite/releases)**

### Android

1. 从 Releases 页面下载 APK 文件
2. 在设备上安装

### Windows

1. 从 Releases 页面下载 Windows 安装包
2. 解压后即可使用

### Web

- [前往](https://secrandom-lite.sectl.cn/)

## 应用截图

<div align="center">

*截图即将添加*

</div>

## 技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| Flutter | >=3.11.0 | 跨平台 UI 框架 |
| Dart | >=3.0.0 | 编程语言 |
| Provider | ^6.1.1 | 状态管理 |
| Material Design 3 | - | UI 设计规范 |
| SharedPreferences | ^2.2.2 | 本地持久化 |
| Excel | ^4.0.6 | Excel 文件解析 |
| File Picker | ^8.0.0 | 文件选择 |

## 项目结构

```
secrandom_lite/
├── lib/
│   ├── main.dart                 # 应用入口
│   ├── models/                   # 数据模型
│   │   ├── student.dart          # 学生模型
│   │   ├── history_record.dart   # 历史记录模型
│   │   └── app_config.dart       # 应用配置模型
│   ├── services/                 # 业务逻辑
│   │   ├── random_service.dart   # 随机抽取服务
│   │   ├── data_service.dart     # 数据服务
│   │   └── excel_import_service.dart # Excel 导入服务
│   ├── providers/                # 状态管理
│   │   ├── app_provider.dart     # 应用状态
│   │   └── auth_provider.dart    # 认证状态
│   ├── screens/                  # 页面
│   │   ├── home_screen.dart      # 主页
│   │   ├── history/              # 历史记录
│   │   └── settings/             # 设置页
│   ├── widgets/                  # 可复用组件
│   │   ├── nav_rail.dart         # 导航栏
│   │   ├── control_panel.dart    # 控制面板
│   │   └── name_display.dart     # 名字显示
│   └── utils/                    # 工具类
├── assets/                       # 资源文件
├── test/                         # 测试文件
├── android/                      # Android 平台代码
├── ios/                          # iOS 平台代码
├── windows/                      # Windows 平台代码
├── macos/                        # macOS 平台代码
├── linux/                        # Linux 平台代码
└── web/                          # Web 平台代码
```

## 快速开始

### 环境要求

- Flutter SDK: >=3.11.0
- Dart SDK: >=3.0.0

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/SECTL/SecRandom-Lite.git
   cd SecRandom-Lite
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **运行应用**
   ```bash
   # 开发模式
   flutter run
   
   # 指定设备
   flutter run -d chrome      # Web
   flutter run -d windows     # Windows
   flutter run -d android     # Android
   ```

### 构建发布版本

```bash
# Android APK
flutter build apk --release

# Windows
flutter build windows --release

# Web
flutter build web --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

## 运行测试

```bash
# 运行所有测试
flutter test

# 运行单元测试
flutter test test/unit_test.dart

# 运行带覆盖率的测试
flutter test --coverage
```

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<!-- 待添加贡献者 -->
<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

## 联系方式

- [QQ群 833875216](https://qm.qq.com/q/iWcfaPHn7W)
- [问题反馈](https://github.com/SECTL/SecRandom-Lite/issues)

## 许可证

本项目基于 [GNU General Public License v3.0](https://opensource.org/licenses/GPL-3.0) 开源。

--------

<div align="center">

**[SecRandom 仓库](https://github.com/SECTL/SecRandom)** | **[SECTL 组织](https://github.com/SECTL)**

</div>

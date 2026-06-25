# gahpc — macOS AHP Proxy Client

**gahpc** 是一个 macOS 菜单栏应用，为 [ahpc-rs](https://github.com/jason-luo/ahpc-rs) Rust 代理引擎提供原生 GUI 界面。支持 AES 加密隧道、RSA 密钥交换、开机自启等特性。

![macOS](https://img.shields.io/badge/macOS-13.0%2B-brightgreen)
![Xcode](https://img.shields.io/badge/Xcode-15.2%2B-blue)
![Rust](https://img.shields.io/badge/Rust-1.70%2B-orange)

---

## 功能

- **菜单栏图标** — 盾牌图标，运行中变绿
- **设置面板** — 图形化配置代理服务器、加密参数、高级选项
- **开机自启** — 通过 `SMAppService` 注册登录项
- **自动运行** — 可设置在应用启动时自动连接代理
- **Rust 核心** — 高性能异步 I/O，多线程 Tokio 运行时
- **多种加密** — AES-128/192/256 CFB/OFB/CTR 共 9 种模式

---

## 截图

```
┌─────────────────────────────────────────┐
│  菜单栏: 🔵 (空闲) / 🟢 (运行中)        │
│                                         │
│  ┌─ 连接设置 ──────────────────────────┐│
│  │ 代理服务器 │ [140.82.49.218] : [8090]││
│  │ 本地绑定   │ [127.0.0.1]    : [8082] ││
│  └──────────────────────────────────────┘│
│  ┌─ 加密设置 ──────────────────────────┐│
│  │ RSA 公钥 (PEM)                       ││
│  │ ┌──────────────────────────────────┐ ││
│  │ │ -----BEGIN PUBLIC KEY-----      │ ││
│  │ │ ...                             │ ││
│  │ └──────────────────────────────────┘ ││
│  │ 加密算法 │ [aes-128-cfb     ▼]      ││
│  │ Auth Key │ [可选               ]    ││
│  └──────────────────────────────────────┘│
│  ┌─ 高级设置 ──────────────────────────┐│
│  │ 超时 (秒)  │ 240 [-] [+]            ││
│  │ 工作线程   │ 2   [-] [+]            ││
│  └──────────────────────────────────────┘│
│  ┌──────────────────────────────────────┐│
│  │ [▶ 启动]        ● 空闲              ││
│  │ [☐ 应用启动时自动运行]              ││
│  └──────────────────────────────────────┘│
└─────────────────────────────────────────┘
```

---

## 前提条件

### 构建环境

| 工具 | 版本要求 |
|---|---|
| macOS | 13.0+ (Ventura) |
| Xcode | 15.2+ |
| Rust | 1.70+ ([rustup](https://rustup.rs)) |
| 目标 | `x86_64-apple-darwin` |

安装 Rust 目标：

```bash
rustup target add x86_64-apple-darwin
```

### 运行环境

- 一个可用的 AHP 代理服务器
- 服务器提供的 RSA 公钥（PEM 格式）

---

## 构建与运行

### 1. 初始化 submodule

```bash
git clone <仓库地址>
cd gahpc
git submodule update --init --recursive
cd ahpc-rs
git checkout feature/static-lib
```

### 2. 编译 Rust 核心库

```bash
cd ahpc-rs
cargo build --release --target x86_64-apple-darwin
cp target/x86_64-apple-darwin/release/libahpc.a target/release/libahpc.a
```

或使用一键脚本：

```bash
bash scripts/build-rust.sh
```

### 3. Xcode 构建

打开 `gahpc.xcodeproj`，选择 **gahpc** target：

- **Debug 构建：** ⌘R 直接运行
- **Release 归档：** Product → Archive → Distribute App → Copy App

> **注意：** Xcode 的 "Build Rust Static Library" 脚本阶段会自动执行 `cargo build`，如果遇到 `cargo: command not found`，检查脚本中 `PATH` 设置。

---

## 使用说明

### 配置

1. 点击菜单栏图标 → **设置**
2. 填写：
   - **代理服务器** — AHP 服务器的地址和端口
   - **RSA 公钥** — 从服务器管理员获取的 PEM 格式公钥
   - **加密算法** — 选择与服务端一致的加密模式
   - **本地绑定** — 本地监听地址（默认 `127.0.0.1:8082`）
3. 其他选项保持默认即可

### 启动

- 点击 **启动** 按钮，菜单栏图标变为绿色 🟢
- 开启 **应用启动时自动运行**，下次启动应用自动连接

### 配置浏览器

将代理设置指向 `127.0.0.1:8082`（或你自定义的端口），即可通过加密隧道访问网络。

---

## 项目结构

```
gahpc/
├── .gitmodules              # Submodule 配置
├── ahpc-rs/                 # Rust 代理核心 (submodule)
│   ├── src/
│   │   ├── lib.rs           # C FFI 导出 (ahpc_start/stop/status)
│   │   ├── config.rs        # 配置解析与校验
│   │   ├── connection.rs    # TCP 监听与加密隧道
│   │   ├── crypto.rs        # AES/RSA/SHA 密码学实现
│   │   └── main.rs          # CLI 入口
│   └── Cargo.toml
├── gahpc/                   # SwiftUI 源码
│   ├── gahpcApp.swift       # App 入口、菜单栏、开机自启
│   ├── ContentView.swift    # 设置面板 UI
│   ├── ConfigModel.swift    # Swift 配置模型与持久化
│   ├── RustBridge.swift     # Rust FFI 桥接封装
│   ├── gahpc-Bridging-Header.h  # C 函数声明
│   └── gahpc.entitlements   # Sandbox 权限
├── gahpc.xcodeproj/         # Xcode 项目
├── scripts/
│   ├── build-rust.sh        # Rust 构建脚本
│   └── setup-xcode.rb       # Xcode 项目配置脚本
└── README.md
```

### 数据流

```
浏览器/应用 ──plaintext──▶ gahpc ──encrypted──▶ AHP 服务器
     ▲                                                │
     └────────────── plaintext ◀──────────────────────┘
```

---

## 常见问题

### `cargo: command not found`

Xcode 构建脚本环境没有 Rust bin 路径。已内置修复，若仍有问题，手动确认：

```bash
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc
```

### `Operation not permitted` 无法监听端口

Sandbox 权限不足。`gahpc.entitlements` 已包含：

```xml
<key>com.apple.security.network.server</key>  <!-- 监听端口 -->
<key>com.apple.security.network.client</key>  <!-- 出站连接 -->
```

### `.app` 体积异常大（800MB+）

检查是否将 `ahpc-rs/target/` 目录打包进了 Resources。正确的 `.app` 应在 **5MB 左右**。

---

## 许可证

[MIT](LICENSE)

---

## 致谢

- [ahpc-rs](https://github.com/jason-luo/ahpc-rs) — Rust 代理核心引擎
- [azure-http-proxy](https://github.com/lxrite/azure-http-proxy) — AHP 协议参考实现

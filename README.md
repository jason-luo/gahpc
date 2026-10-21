# gahpc — macOS AHP Proxy Client

**gahpc** 是一个 macOS 菜单栏应用，为 [ahpc-rs](https://github.com/jason-luo/ahpc-rs) Rust 代理引擎提供原生 GUI 界面。支持 AES 加密隧道、RSA 密钥交换、开机自启等特性。

![macOS](https://img.shields.io/badge/macOS-13.1%2B-brightgreen)
![Xcode](https://img.shields.io/badge/Xcode-15.2%2B-blue)
![Rust](https://img.shields.io/badge/Rust-1.70%2B-orange)

---

## 功能

- **菜单栏图标** — 盾牌图标，运行中切换为实心
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
│  │ 代理服务器 │ [198.51.100.10] : [8090]││
│  │ 本地绑定   │ [127.0.0.1]    : [8089] ││
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

> 示例中的服务器地址使用文档保留地址 `198.51.100.10`，不是实际服务器。

---

## 前提条件

### 构建环境

| 工具 | 版本要求 |
|---|---|
| macOS | 13.1+ (Ventura) |
| Xcode | 15.2+ |
| Rust | 1.70+ ([rustup](https://rustup.rs)) |
| 目标 | `x86_64-apple-darwin` |

安装 Rust 目标：

```bash
rustup target add x86_64-apple-darwin
```

> 当前工程只构建 `x86_64`。Apple Silicon 机器需要安装 Rosetta 才能运行；原生 arm64/Universal 构建暂未启用。

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
cargo build --release --locked --target x86_64-apple-darwin
cp target/x86_64-apple-darwin/release/libahpc.a target/release/libahpc.a
```

或使用一键脚本：

```bash
bash scripts/build-rust.sh
```

### 3. Xcode 构建

打开 `gahpc.xcodeproj`，选择 **gahpc** target：

- **Debug 构建：** ⌘R 直接运行
- **Release 构建：** Product → Build，随后用 Product → Show Build Folder in Finder 查看 `gahpc.app`

本项目面向自用和源码分发，使用 **ad-hoc 签名**，不使用 Developer ID，也不做公证。如果 Xcode 没有自动签名，可以手动签名：

```bash
codesign --force --sign - \
  --entitlements gahpc/gahpc.entitlements \
  "<path-to-gahpc.app>"
```

测试登录项时，请先把 app 放到 `/Applications`；首次读取 Keychain 可能需要在系统弹窗中允许。

> **注意：** Xcode 的 "Build Rust Static Library" 脚本阶段会自动执行 `cargo build`，如果遇到 `cargo: command not found`，检查脚本中 `PATH` 设置。

### 4. 运行测试

测试 target `gahpcTests` 直接编译 `ConfigModel.swift`，不依赖 Rust 静态库或 GUI：

```bash
xcodebuild \
  -project gahpc.xcodeproj \
  -scheme gahpcTests \
  -configuration Debug \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath build/TestDerivedData \
  build CODE_SIGNING_ALLOWED=NO

xcrun xctest build/TestDerivedData/Build/Products/Debug/gahpcTests.xctest
```

CI 配置在 `.github/workflows/ci.yml`。

---

## 使用说明

### 配置

1. 点击菜单栏图标 → **设置**
2. 填写：
   - **代理服务器** — AHP 服务器的地址和端口
   - **RSA 公钥** — 从服务器管理员获取的 PEM 格式公钥
   - **加密算法** — 选择与服务端一致的加密模式
   - **本地绑定** — 本地监听地址（默认 `127.0.0.1:8089`）
3. 其他选项保持默认即可

### 启动

- 点击 **启动** 按钮，菜单栏图标切换为实心盾牌
- 开启 **应用启动时自动运行**，下次启动应用自动连接

### 配置浏览器

将代理设置指向 `127.0.0.1:8089`（或你自定义的端口），即可通过加密隧道访问网络。

---

## 项目结构

```
gahpc/
├── .github/workflows/ci.yml # GitHub Actions 构建与测试
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
│   ├── ProxyController.swift # 代理状态与 FFI 调度
│   ├── RustBridge.swift     # Rust FFI 桥接封装
│   ├── gahpc-Bridging-Header.h  # C 函数声明
│   └── gahpc.entitlements   # Sandbox 权限
├── gahpcTests/
│   └── ConfigModelTests.swift # 配置校验与解码测试
├── gahpc.xcodeproj/         # Xcode 项目
├── scripts/
│   ├── build-rust.sh        # Rust 构建脚本
│   └── setup-xcode.rb       # Xcode 项目配置脚本
├── LICENSE
└── README.md
```

### 数据流

```
浏览器/应用 ──plaintext──▶ gahpc ──encrypted──▶ AHP 服务器
     ▲                                                │
     └────────────── plaintext ◀──────────────────────┘
```

---

## 分发方式

本项目按 **自用 + 源码分发** 配置：

- 不使用 Developer ID，不做公证，不提供可信的预编译分发包。
- 自己构建出的 `.app` 是 ad-hoc 签名；复制到其他 Mac 时可能被 Gatekeeper 拦截，需要手动允许。
- 源码分发时，接收方需要自行安装 Xcode/Rust 并构建。
- 当前只支持 `x86_64`；Apple Silicon 需要 Rosetta，原生 arm64/Universal 暂未启用。

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

### Auth Key 存在哪里？

Auth Key 保存在 Keychain 中：

- service: `xyz.luoxy.gahpc`
- account: `auth_key`

`UserDefaults` 里的 `proxy_config` 不再保存明文 Auth Key。ad-hoc 重新构建后，macOS 可能再次弹出 Keychain 授权，点“始终允许”即可。

### 登录时自动启动失败

请确认：

1. app 已放到 `/Applications`。
2. 系统设置 → 通用 → 登录项中允许该 app。
3. 当前是 ad-hoc 签名，`SMAppService` 可能被 macOS 拒绝；这是签名限制，不代表配置错误。

### 提示“无法验证开发者”

本地构建通常不会触发；如果 app 经过压缩/网络传输后再打开，可能带上 quarantine 标记。确认来源可信后可以：

```bash
xattr -dr com.apple.quarantine /Applications/gahpc.app
```

ad-hoc 签名下 `spctl` 校验失败是正常现象，不等于 app 无法运行。

### `.app` 体积异常大（800MB+）

检查是否将 `ahpc-rs/target/` 目录打包进了 Resources。正确的 `.app` 应在 **5MB 左右**。

---

## 许可证

[MIT](LICENSE)

---

## 致谢

- [ahpc-rs](https://github.com/jason-luo/ahpc-rs) — Rust 代理核心引擎
- [azure-http-proxy](https://github.com/lxrite/azure-http-proxy) — AHP 协议参考实现

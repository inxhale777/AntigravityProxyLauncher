# Antigravity Proxy Launcher (English fork)

An English-language build of [OpsinTech/AntigravityProxyLauncher](https://github.com/OpsinTech/AntigravityProxyLauncher) v2.8.0 for Apple Silicon Macs.
The original README (Chinese) is kept as [README.upstream-zh.md](README.upstream-zh.md).

The launcher routes the Antigravity / Gemini desktop apps through a proxy of your choice. It copies the app, injects a networking library into the copy, and can optionally reroute model API requests to other providers.

## What differs from upstream

- **English interface.** All UI text is translated.
- **No activation screen.** Upstream asks for a code obtained through the author's WeChat account.
- **No update checks by default.** The app makes no requests to GitHub about new versions. If you turn *Check for updates* on in Settings, it checks this fork.
- **Apple Silicon only.** Releases are arm64 builds.

Nothing else was changed: proxy injection, the repair flow and model routing are upstream code.

## Install

1. Download `AntigravityProxyLauncher_<version>_macos_arm64.zip` from [Releases](../../releases) and unzip it to `/Applications`.
2. The app is signed ad hoc (there is no Apple Developer ID), so macOS warns on first launch. Right-click the app and choose *Open*, or run:

   ```bash
   xattr -cr /Applications/AntigravityProxyLauncher.app
   ```

## Use

1. Start your proxy client first.
2. In **Proxy Settings** enter the proxy host and port, then click **Detect**.
3. In **Run Status** select the target app and click **Repair**.
4. When the status says repair is complete, click **Launch**.

The injected library speaks **SOCKS5** to your proxy, so point it at a SOCKS5 port. An HTTP port works only for the model-routing gateway.

## Build from source

Requirements: macOS with Xcode, Go 1.24 or newer, and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
bash scripts/build_en.sh
# result: build_output/en/AntigravityProxyLauncher.app
```

## Good to know

- **Local gateway.** While the launcher runs, its gateway listens on all network interfaces, port `18081`, without authentication. Anyone on the same network can use it.
- **Patched copy.** The patched app is started without Keychain protection, so its stored secrets are not encrypted.
- **Terms and availability.** Patching Google's app may fall outside Google's terms. Antigravity is not available in every country, and the launcher cannot change that.

## License

MIT, see [LICENSE](LICENSE). Original work Copyright (c) 2024 KevinLiangX; changes in this fork are released under the same license.
This project is not affiliated with Google or with the original author. Antigravity and Gemini are trademarks of Google LLC.

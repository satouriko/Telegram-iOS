# Nekogram Lite

> iOS 上可复读的 Telegram

## 编译指南（开发版）

1. 填充 `telegram-configuration/provision`
2. 生成 Xcode 项目
    ```
    python3 build-system/Make/Make.py \
        --bazel="/opt/homebrew/bin/bazel" \
        --cacheDir="telegram-bazel-cache" \
        generateProject --bazel_x86_64="/usr/local/bin/bazel" \
        --configurationPath="telegram-configuration" \
        --disableExtensions
    ```
3. 打开 Xcode，选择 PROJECT Telegram -> TARGETS Telegram -> Signing & Capabilities -> 设置 Provisioning Profile
4. 转到 Build Settings -> Signing -> 设置 Code Signing Identity
5. 转到 Signing & Capabilities -> + Capability -> App Groups

## 编译指南（发行版）

1. 填充 `telegram-configuration-dist/provision`
2. 编译项目
    ```
    python3 build-system/Make/Make.py \
        --bazel="/opt/homebrew/bin/bazel" \
        --cacheDir="telegram-bazel-cache" \
        build \
        --configurationPath="telegram-configuration-dist" \
        --buildNumber=100001 \
        --configuration=release_universal
    ```

## 姊妹项目

- [Android](https://github.com/satouriko/nekolite)

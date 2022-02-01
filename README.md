<p style="text-align: center; font-style: italic" align="center"><i>「<ruby>
  小さ<rp>(</rp><rt>Chiisa</rt><rp>)</rp>
  な<rp>(</rp><rt>na</rt><rp>)</rp>
  体<rp>(</rp><rt>karada</rt><rp>)</rp>
  でも<rp>(</rp><rt>demo</rt><rp>)</rp>
  ギリギリ<rp>(</rp><rt>girigiri</rt><rp>)</rp>
  まで<rp>(</rp><rt>made</rt><rp>)</rp>
  乗り<rp>(</rp><rt>nori</rt><rp>)</rp>
  出して<rp>(</rp><rt>dashite</rt><rp>)</rp>
</ruby><br><ruby>
  伸ばした<rp>(</rp><rt>nobashita</rt><rp>)</rp>
  手<rp>(</rp><rt>te</rt><rp>)</rp>
  を<rp>(</rp><rt>o</rt><rp>)</rp>
  ぎゅっと<rp>(</rp><rt>gyutto</rt><rp>)</rp>
</ruby><br><ruby>
  つか<rp>(</rp><rt>tsuka</rt><rp>)</rp>
  んで<rp>(</rp><rt>nde</rt><rp>)</rp>
  欲しい<rp>(</rp><rt>hoshii</rt><rp>)</rp>
  の<rp>(</rp><rt>no</rt><rp>)</rp>
  です<rp>(</rp><rt>desu</rt><rp>)</rp>
</ruby>」</i></p>

<p style="text-align: right; font-style: italic" align="right"><i>——《なのです!》</i></p>

---

# Nanogram

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
3. 打开 Xcode，选择 PROJECT Telegram -> TARGETS Telegram -> Signing & Capabilities ->
   设置 Provisioning Profile
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

- [Android 版](https://github.com/satouriko/nanogram-android)

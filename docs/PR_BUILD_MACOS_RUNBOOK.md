# RouteFlow PR 构建包（macOS）启动说明

适用包名：`RouteFlow-pr-<PR号>-<SHA>.app.zip`

当你从浏览器、IM 或 CI 下载该包时，macOS 可能给 `.app` 增加隔离属性（`com.apple.quarantine`），导致双击无法启动。按下面步骤处理即可。

## 1) 解压并放置应用

```bash
unzip RouteFlow-pr-<PR号>-<SHA>.app.zip
mv RouteFlow*.app /Applications/
```

## 2) 去掉隔离属性（关键步骤）

```bash
xattr -dr com.apple.quarantine "/Applications/RouteFlow-pr-<PR号>-<SHA>.app"
```

如果你改过应用名，请把命令里的路径改成实际 `.app` 路径。

## 3) 启动应用

```bash
open "/Applications/RouteFlow-pr-<PR号>-<SHA>.app"
```

## 4) 排障

- 仍然提示“无法打开”时，先检查是否还带隔离属性：

```bash
xattr -p com.apple.quarantine "/Applications/RouteFlow-pr-<PR号>-<SHA>.app"
```

- 如果上面命令仍有输出，再执行一次去隔离命令；目录无权限时改用 `sudo`：

```bash
sudo xattr -dr com.apple.quarantine "/Applications/RouteFlow-pr-<PR号>-<SHA>.app"
```

## 5) 安全提醒

只对你信任来源的构建包执行上述命令。推荐先核对 PR 号、提交 SHA 和发布来源，再解除隔离并运行。

---

# RouteFlow PR Build (macOS) Launch Guide

Target package: `RouteFlow-pr-<PR-number>-<SHA>.app.zip`

When downloaded from a browser, chat app, or CI artifact, macOS may attach `com.apple.quarantine` to the app and block launch. Use the steps below.

## 1) Unzip and place the app

```bash
unzip RouteFlow-pr-<PR-number>-<SHA>.app.zip
mv RouteFlow*.app /Applications/
```

## 2) Remove quarantine (required)

```bash
xattr -dr com.apple.quarantine "/Applications/RouteFlow-pr-<PR-number>-<SHA>.app"
```

## 3) Launch

```bash
open "/Applications/RouteFlow-pr-<PR-number>-<SHA>.app"
```

## 4) Troubleshooting

- Check whether quarantine is still present:

```bash
xattr -p com.apple.quarantine "/Applications/RouteFlow-pr-<PR-number>-<SHA>.app"
```

- If it still exists, run removal again. Use `sudo` if permission is denied:

```bash
sudo xattr -dr com.apple.quarantine "/Applications/RouteFlow-pr-<PR-number>-<SHA>.app"
```

## 5) Security note

Run these commands only for trusted artifacts. Verify the PR number, commit SHA, and artifact source before removing quarantine.

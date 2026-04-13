# Mail Analyzer Flutter Client

Flutter 移动端客户端（Android / iOS，对接当前 Flask API）。

## 已完成

- 登录页（调用 `/api/auth/login`）
- 会话/CSRF 持久化
- 首页四个模块：
  - 邮件（`/api/emails`）
  - 日程（`/api/events`）
  - 任务（`/api/tasks/active`，3 秒轮询）
  - 设置（通知开关本地保存）
- 本地通知（任务状态变化提醒）
- FCM 接入（前台消息展示、本机 Token 获取）

## 本地启动（首次）

1. 安装 Flutter SDK 并加入 PATH
2. 进入目录：
   - `cd mobile/mail_analyzer_app`
3. 生成平台工程（只需首次）：
   - `flutter create .`
4. 拉依赖：
   - `flutter pub get`
5. 运行：
   - `flutter run`

## 后端地址

默认地址在 `lib/core/config/app_config.dart`：

- `http://127.0.0.1:5055`

如果真机调试，改为电脑局域网 IP（如 `http://192.168.1.10:5055`）。

## FCM 配置（Android）

1. 在 Firebase 控制台创建 Android 应用（包名默认是 `com.harrydi.mail_analyzer_app`）。
2. 下载配置文件并放到：
   - `android/app/google-services.json`
3. 重新执行：
   - `flutter pub get`
   - `flutter run` 或 `flutter build apk`
4. 在 App 的“设置 -> 通知设置”里点击“刷新 FCM Token”确认通道已就绪。

> 未放置 `google-services.json` 时，App 仍可正常编译和使用本地通知，但 FCM 推送通道不会生效。

## FCM 配置（iOS）

1. 在 Firebase 控制台创建 iOS 应用（Bundle ID 需与 Xcode 中 `Runner` 一致）。
2. 下载配置文件并放到：
   - `ios/Runner/GoogleService-Info.plist`
3. 在 Mac 上打开 `ios/Runner.xcworkspace`，给 `Runner` 打开能力：
   - `Push Notifications`
   - `Background Modes`（勾选 `Remote notifications`）
4. 执行：
   - `flutter clean`
   - `flutter pub get`
   - `cd ios && pod install && cd ..`
5. 真机运行后，到 App “设置 -> 通知设置”里刷新 FCM Token，看到 token 即表示通道正常。

> 未放置 `GoogleService-Info.plist` 时，iOS 端仍可运行，但 FCM 不会生效。

## iOS 测试说明

- iOS 编译和真机调试必须在 macOS 上进行（Windows 不能直接编译 iOS）。
- 最快测试方式：
  1. 把当前项目拷到 Mac
  2. 安装 Xcode、CocoaPods、Flutter
  3. 运行 `flutter doctor` 确认通过
  4. 连 iPhone（并在手机“设置 -> 隐私与安全”信任开发者）
  5. 在项目目录执行 `flutter run -d <你的iPhone设备ID>`
- 测试 FCM：
  - 用 Firebase Console 发送测试消息到该设备 token
  - 验证前台/后台都能收到（后台依赖系统策略与权限）

## 下一步建议

- 加入 Dio CookieManager，完整处理会话 Cookie
- 增加邮件详情页、事件编辑页
- 邮件批量同步 Notion（选中/全部）
- 统一状态管理（Riverpod/Bloc）

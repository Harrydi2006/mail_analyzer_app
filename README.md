# Mail Analyzer Flutter Client

Flutter Android 客户端骨架（对接当前 Flask API）。

## 已完成

- 登录页（调用 `/api/auth/login`）
- 会话/CSRF 持久化
- 首页四个模块：
  - 邮件（`/api/emails`）
  - 日程（`/api/events`）
  - 任务（`/api/tasks/active`，3 秒轮询）
  - 设置（通知开关本地保存）
- 通知服务占位（后续接入 FCM/本地通知）

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

## 下一步建议

- 加入 Dio CookieManager，完整处理会话 Cookie
- 增加邮件详情页、事件编辑页
- 接入 FCM 推送和 `flutter_local_notifications`
- 统一状态管理（Riverpod/Bloc）

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../home/home_page.dart';
import 'auth_repository.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authRepo = AuthRepository();

  bool _loading = false;
  String? _error;
  String _currentBaseUrl = AppConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _initAndTryAutoLogin();
  }

  Future<void> _initAndTryAutoLogin() async {
    await AppConfig.loadBaseUrlOverride();
    ApiClient.instance.setBaseUrl(AppConfig.baseUrl);
    if (!mounted) return;
    setState(() => _currentBaseUrl = AppConfig.baseUrl);
    await _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final ok = await _authRepo.checkAuth();
    if (!mounted || !ok) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await _authRepo.login(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _error = '登录失败，请检查账号密码或服务地址');
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '网络异常，请检查后端是否已启动');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openBaseUrlSettingsPage() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _BaseUrlSettingsPage()),
    );
    if (!mounted || changed != true) return;
    final baseUrl = AppConfig.baseUrl;
    setState(() => _currentBaseUrl = baseUrl);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('服务地址已更新：$baseUrl')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mail_outline, size: 52),
                    const SizedBox(height: 12),
                    const Text(
                      'Mail Analyzer',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                    ),
                    const SizedBox(height: 12),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '服务地址：$_currentBaseUrl',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _openBaseUrlSettingsPage,
                        icon: const Icon(Icons.settings_ethernet),
                        label: const Text('服务地址设置'),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('登录'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}

class _BaseUrlSettingsPage extends StatefulWidget {
  const _BaseUrlSettingsPage();

  @override
  State<_BaseUrlSettingsPage> createState() => _BaseUrlSettingsPageState();
}

class _BaseUrlSettingsPageState extends State<_BaseUrlSettingsPage> {
  final TextEditingController _controller = TextEditingController(text: AppConfig.baseUrl);
  bool _testing = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _normalizeInput() {
    var value = _controller.text.trim();
    if (value.isEmpty) return '请输入地址';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '地址格式不正确';
    }
    _controller.text = value;
    return null;
  }

  Future<void> _save() async {
    final err = _normalizeInput();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final value = _controller.text.trim();
    await AppConfig.setBaseUrlOverride(value);
    ApiClient.instance.setBaseUrl(AppConfig.baseUrl);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _resetDefault() async {
    await AppConfig.setBaseUrlOverride(null);
    ApiClient.instance.setBaseUrl(AppConfig.baseUrl);
    if (!mounted) return;
    setState(() {
      _controller.text = AppConfig.baseUrl;
      _error = null;
    });
  }

  Future<void> _testConnection() async {
    final err = _normalizeInput();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      final value = _controller.text.trim();
      await AppConfig.setBaseUrlOverride(value);
      ApiClient.instance.setBaseUrl(AppConfig.baseUrl);
      final res = await ApiClient.instance.get('/api/auth/check');
      if (!mounted) return;
      final code = res.statusCode ?? 0;
      final body = res.data;
      final detail = body is Map<String, dynamic>
          ? (body['message']?.toString() ?? body['error']?.toString() ?? '服务可访问')
          : '服务可访问';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('连接成功（HTTP $code）：$detail')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接失败：$e')));
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务地址设置')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: 'http://192.168.1.100:5000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: const Text('测试连接'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _save,
              child: const Text('保存并返回'),
            ),
            TextButton(
              onPressed: _resetDefault,
              child: const Text('恢复默认地址'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../auth/auth_repository.dart';
import '../auth/login_page.dart';
import '../emails/emails_page.dart';
import '../events/events_page.dart';
import '../home/dashboard_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final _authRepo = AuthRepository();

  final _pages = const [
    DashboardPage(),
    EmailsPage(),
    EventsPage(),
    SettingsPage(),
  ];

  final _titles = const [
    '首页',
    '邮件管理',
    '日程表',
    '系统设置',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authRepo.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.mail_outline), label: '邮件'),
          NavigationDestination(icon: Icon(Icons.event_note), label: '日程'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

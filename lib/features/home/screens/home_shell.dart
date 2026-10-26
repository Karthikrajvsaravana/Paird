import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../discover/screens/discover_screen.dart';
import '../../matches/screens/matches_screen.dart';
import '../../messaging/screens/conversations_screen.dart';
import '../../profile/screens/my_profile_screen.dart';

/// Signed-in app shell with bottom navigation.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  int _pendingInterests = 0;
  int _unreadMessages = 0;
  Timer? _badgeTimer;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshBadges());
    // Badge counts are refreshed by polling (not push) while the app is open.
    _badgeTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshBadges(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _badgeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshBadges();
  }

  Future<void> _refreshBadges() async {
    try {
      final data = await AppScope.read(context).api.dashboard();
      if (!mounted) return;
      final counts = data['counts'] as Map;
      setState(() {
        _pendingInterests = counts['interests_received'] as int? ?? 0;
        _unreadMessages = counts['unread_messages'] as int? ?? 0;
      });
    } catch (_) {
      // Badges are best-effort; screens show their own errors.
    }
  }

  void goTo(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
    _refreshBadges();
  }

  Widget _badge(IconData icon, int count, String label) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: Icon(icon, semanticLabel: count > 0 ? '$count new' : null),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onNavigate: goTo),
      const DiscoverScreen(),
      MatchesScreen(onChanged: _refreshBadges),
      ConversationsScreen(onChanged: _refreshBadges),
      const MyProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < pages.length; i++)
            _visited.contains(i) ? pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: goTo,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: _badge(Icons.favorite_border, _pendingInterests, 'Matches'),
            selectedIcon: _badge(Icons.favorite, _pendingInterests, 'Matches'),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: _badge(
              Icons.chat_bubble_outline,
              _unreadMessages,
              'Messages',
            ),
            selectedIcon: _badge(
              Icons.chat_bubble,
              _unreadMessages,
              'Messages',
            ),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

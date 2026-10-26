import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../discover/screens/member_profile_screen.dart';
import '../../messaging/screens/chat_screen.dart';

/// Mutual matches plus received and sent interests.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  int _version = 0;

  void _changed() {
    setState(() => _version++);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Matches'),
          bottom: TabBar(
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: AppTheme.sans(weight: FontWeight.w600),
            tabs: const [Tab(text: 'Matches'), Tab(text: 'Received'), Tab(text: 'Sent')],
          ),
        ),
        body: TabBarView(
          children: [
            _MatchList(key: ValueKey('m$_version'), onChanged: _changed),
            _InterestList(key: ValueKey('r$_version'), direction: 'received', onChanged: _changed),
            _InterestList(key: ValueKey('s$_version'), direction: 'sent', onChanged: _changed),
          ],
        ),
      ),
    );
  }
}

class _MatchList extends StatefulWidget {
  const _MatchList({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_MatchList> createState() => _MatchListState();
}

class _MatchListState extends State<_MatchList> with AutomaticKeepAliveClientMixin {
  Future<Paged<MatchItem>>? _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = AppScope.read(context).api.matches();
  }

  Future<void> _reload() async {
    setState(() => _future = AppScope.read(context).api.matches());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<Paged<MatchItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
        if (snapshot.hasError) {
          return ErrorView(message: (snapshot.error as ApiException?)?.message ?? 'Could not load matches.', onRetry: _reload);
        }
        final items = snapshot.data!.items;
        return RefreshIndicator(
          onRefresh: _reload,
          child: items.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  EmptyView(
                    icon: Icons.favorite_border,
                    title: 'No matches yet',
                    message: 'When someone accepts your interest — or you accept theirs — you’ll match here.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final m = items[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        leading: MemberPhoto(url: m.member.photoUrl, name: m.member.displayName),
                        title: Row(children: [
                          Flexible(child: Text(m.member.displayName, overflow: TextOverflow.ellipsis)),
                          if (m.member.isVerified) ...[const SizedBox(width: 6), const VerifiedBadge()],
                        ]),
                        subtitle: Text('Matched ${timeAgo(m.createdAt)}',
                            style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
                        trailing: IconButton(
                          tooltip: 'Message ${m.member.displayName}',
                          icon: Badge(
                            isLabelVisible: m.unreadCount > 0,
                            label: Text('${m.unreadCount}'),
                            child: const Icon(Icons.chat_bubble_outline, color: AppColors.gold),
                          ),
                          onPressed: m.conversationId == null
                              ? null
                              : () async {
                                  await Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ChatScreen(conversationId: m.conversationId!, title: m.member.displayName),
                                  ));
                                  widget.onChanged();
                                },
                        ),
                        onTap: () async {
                          final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                            builder: (_) => MemberProfileScreen(userId: m.member.userId, preview: m.member),
                          ));
                          if (changed == true) widget.onChanged();
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _InterestList extends StatefulWidget {
  const _InterestList({super.key, required this.direction, required this.onChanged});
  final String direction;
  final VoidCallback onChanged;

  @override
  State<_InterestList> createState() => _InterestListState();
}

class _InterestListState extends State<_InterestList> with AutomaticKeepAliveClientMixin {
  Future<Paged<Interest>>? _future;
  final _busy = <int>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paged<Interest>> _fetch() => AppScope.read(context).api.interests(direction: widget.direction);

  Future<void> _reload() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<void> _act(Interest interest, String action, String message) async {
    if (_busy.contains(interest.id)) return;
    setState(() => _busy.add(interest.id));
    try {
      await AppScope.read(context).api.interestAction(interest.id, action);
      if (mounted) showSnack(context, message);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
      _reload();
    } finally {
      if (mounted) setState(() => _busy.remove(interest.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final received = widget.direction == 'received';
    return FutureBuilder<Paged<Interest>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
        if (snapshot.hasError) {
          return ErrorView(message: (snapshot.error as ApiException?)?.message ?? 'Could not load interests.', onRetry: _reload);
        }
        final items = snapshot.data!.items;
        return RefreshIndicator(
          onRefresh: _reload,
          child: items.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 80),
                  EmptyView(
                    icon: received ? Icons.inbox_outlined : Icons.send_outlined,
                    title: received ? 'No pending interests' : 'No pending interests sent',
                    message: received
                        ? 'Interests you receive appear here. They expire if not answered in time.'
                        : 'Send interests from Discover. Pending interests expire if not answered.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final interest = items[i];
                    final m = interest.member;
                    final busy = _busy.contains(interest.id);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InkWell(
                              onTap: () async {
                                final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                                  builder: (_) => MemberProfileScreen(userId: m.userId, preview: m),
                                ));
                                if (changed == true) widget.onChanged();
                              },
                              child: Row(
                                children: [
                                  MemberPhoto(url: m.photoUrl, name: m.displayName, hidden: m.photosHidden),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m.displayName, style: AppTheme.serif(size: 20)),
                                        if (m.headline.isNotEmpty)
                                          Text(m.headline, style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
                                        Text(timeLeft(interest.expiresAt),
                                            style: AppTheme.sans(size: 12, color: AppColors.gold)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (interest.note.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('“${interest.note}”', style: AppTheme.sans(size: 13, color: AppColors.textLabel)),
                            ],
                            const SizedBox(height: 10),
                            if (received)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: busy ? null : () => _act(interest, 'decline', 'Interest declined.'),
                                      child: const Text('Decline'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: GoldButton(
                                      label: 'Accept',
                                      busy: busy,
                                      onPressed: () => _act(interest, 'accept', "It's a match with ${m.displayName}!"),
                                    ),
                                  ),
                                ],
                              )
                            else
                              OutlinedButton(
                                onPressed: busy ? null : () => _act(interest, 'withdraw', 'Interest withdrawn.'),
                                child: const Text('Withdraw'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

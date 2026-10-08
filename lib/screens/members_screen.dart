import 'package:flutter/material.dart';

import '../models.dart';
import '../services/repository.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Validation des nouveaux comptes et attribution des rôles (admin uniquement).
class MembersPanel extends StatefulWidget {
  final Future<List<Profile>> Function()? load;
  final Future<void> Function(String id, MemberRole role)? setRole;

  const MembersPanel({super.key, this.load, this.setRole});

  @override
  State<MembersPanel> createState() => _MembersPanelState();
}

class _MembersPanelState extends State<MembersPanel> {
  late Future<List<Profile>> _profiles = _fetch();

  Future<List<Profile>> _fetch() => (widget.load ?? Repository.instance.profiles)();

  Future<void> _setRole(Profile p, MemberRole role) async {
    await (widget.setRole ?? Repository.instance.setRole)(p.id, role);
    setState(() => _profiles = _fetch());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Profile>>(
      future: _profiles,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final pending = snap.data!.where((p) => !p.isApproved).toList();
        final members = snap.data!.where((p) => p.isApproved).toList();
        return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          ContentWidth(
            maxWidth: 800,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text('Membres', style: theme.textTheme.headlineLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('${members.length} membres · ${pending.length} en attente',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              if (pending.isNotEmpty) ...[
                const SectionHeader('À valider'),
                for (final p in pending)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Card(
                      color: AppColors.gold.withValues(alpha: 0.12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        leading: Avatar(p.fullName),
                        title: Text(p.fullName.isEmpty ? 'Sans nom' : p.fullName),
                        subtitle: const Text('Demande à rejoindre la chorale'),
                        trailing: FilledButton(
                          onPressed: () => _setRole(p, MemberRole.membre),
                          child: const Text('Valider'),
                        ),
                      ),
                    ),
                  ),
              ],
              const SectionHeader('Chorale'),
              for (final p in members)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: Avatar(p.fullName),
                      title: Text(p.fullName.isEmpty ? 'Sans nom' : p.fullName),
                      subtitle: Text(roleLabel(p.role)),
                      trailing: PopupMenuButton<MemberRole>(
                        tooltip: 'Changer le rôle',
                        icon: const Icon(Icons.manage_accounts_rounded),
                        onSelected: (r) => _setRole(p, r),
                        itemBuilder: (_) => [
                          for (final r in MemberRole.values) PopupMenuItem(value: r, child: Text(roleLabel(r))),
                        ],
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

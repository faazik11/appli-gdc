import 'package:flutter/material.dart';

import '../models.dart';
import '../services/repository.dart';

/// Validation des nouveaux comptes et attribution des rôles (admin uniquement).
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _repo = Repository.instance;
  late Future<List<Profile>> _profiles = _repo.profiles();

  Future<void> _setRole(Profile p, MemberRole role) async {
    await _repo.setRole(p.id, role);
    setState(() => _profiles = _repo.profiles());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membres')),
      body: FutureBuilder<List<Profile>>(
        future: _profiles,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final profiles = [...snap.data!]
            ..sort((a, b) => (a.isApproved ? 1 : 0).compareTo(b.isApproved ? 1 : 0));
          return ListView(children: [
            for (final p in profiles)
              ListTile(
                leading: Icon(p.isApproved ? Icons.person : Icons.person_add_alt,
                    color: p.isApproved ? null : Theme.of(context).colorScheme.primary),
                title: Text(p.fullName.isEmpty ? 'Sans nom' : p.fullName),
                subtitle: Text(roleLabel(p.role)),
                trailing: p.isApproved
                    ? PopupMenuButton<MemberRole>(
                        onSelected: (r) => _setRole(p, r),
                        itemBuilder: (_) => [
                          for (final r in MemberRole.values)
                            PopupMenuItem(value: r, child: Text(roleLabel(r))),
                        ],
                      )
                    : FilledButton(
                        onPressed: () => _setRole(p, MemberRole.membre),
                        child: const Text('Valider'),
                      ),
              ),
          ]);
        },
      ),
    );
  }
}

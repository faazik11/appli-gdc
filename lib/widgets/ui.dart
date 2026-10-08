import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../theme.dart';

/// Limite la largeur du contenu sur grand écran.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = 1100});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 12, 12),
      child: Row(children: [
        Container(width: 4, height: 22, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ]),
    );
  }
}

/// Pastille dégradée avec l'icône d'une catégorie.
class CategoryIcon extends StatelessWidget {
  final CategoryStyle style;
  final double size;

  const CategoryIcon(this.style, {super.key, this.size = 48});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: style.gradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [BoxShadow(color: style.colors.first.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(style.icon, color: Colors.white, size: size * 0.5),
      );
}

/// Petites icônes indiquant ce qui est disponible pour un chant.
class MediaBadges extends StatelessWidget {
  final Song song;

  const MediaBadges(this.song, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget badge(IconData icon, Color color, String tooltip) => Tooltip(
          message: tooltip,
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: color),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (song.hasPdf) badge(Icons.description_rounded, const Color(0xFF5B6B8C), 'Paroles PDF'),
      if (song.hasYoutube) badge(Icons.smart_display_rounded, const Color(0xFFD93025), 'Vidéo YouTube'),
      if (song.hasAudio) badge(Icons.headphones_rounded, const Color(0xFF0E8A6E), 'Audio'),
    ]);
  }
}

class SongCard extends StatelessWidget {
  final Song song;
  final Category? category;
  final VoidCallback onTap;

  const SongCard({super.key, required this.song, required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = CategoryStyle.of(category?.name ?? '');
    final subtitle = [
      if (category != null) category!.name,
      ...song.tags.take(3),
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CategoryIcon(style, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            MediaBadges(song),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// Carte de catégorie en dégradé, avec le nombre de chants.
class CategoryCard extends StatelessWidget {
  final String name;
  final int count;
  final String countLabel;
  final VoidCallback onTap;

  const CategoryCard({super.key, required this.name, required this.count, required this.countLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(name);
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: style.gradient),
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            Positioned(
              right: -18,
              bottom: -18,
              child: Icon(style.icon, size: 110, color: Colors.white.withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                  child: Icon(style.icon, color: Colors.white, size: 22),
                ),
                const Spacer(),
                Text(name,
                    maxLines: 2,
                    style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16, height: 1.2)),
                const SizedBox(height: 2),
                Text('$count $countLabel',
                    style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Carte « couverture » d'un livret.
class BookletCard extends StatelessWidget {
  final Booklet booklet;
  final VoidCallback? onTap;
  final Widget? menu;

  const BookletCard({super.key, required this.booklet, this.onTap, this.menu});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = booklet.eventDate == null ? null : DateFormat.yMMMMd('fr_FR').format(booklet.eventDate!);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 110,
            decoration: BoxDecoration(gradient: CategoryStyle.of('Livrets').gradient),
            child: Stack(children: [
              Positioned(
                right: -10,
                bottom: -16,
                child: Icon(Icons.menu_book_rounded, size: 96, color: Colors.white.withValues(alpha: 0.13)),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(booklet.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'DMSerifDisplay', fontFamilyFallback: ['Amiri'], color: Colors.white, fontSize: 20, height: 1.15)),
                ),
              ),
              if (menu != null) Positioned(top: 2, right: 2, child: IconTheme(data: const IconThemeData(color: Colors.white), child: menu!)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(children: [
              Icon(Icons.event_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(date ?? 'Sans date',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ),
              if (booklet.songCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: Text('${booklet.songCount} chants',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.tertiary, fontWeight: FontWeight.w600)),
                )
              else
                Text('PDF importé', style: theme.textTheme.labelSmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, size: 40, color: theme.colorScheme.tertiary),
        ),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ]),
    );
  }
}

/// Logo de l'appli : note de musique dorée dans un cercle.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [AppColors.goldLight, AppColors.gold]),
          boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Icon(Icons.music_note_rounded, color: AppColors.aubergine, size: size * 0.55),
      );
}

class Avatar extends StatelessWidget {
  final String name;
  final double radius;

  const Avatar(this.name, {super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.gold,
      foregroundColor: AppColors.aubergine,
      child: Text(initials.isEmpty ? '?' : initials,
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: radius * 0.75)),
    );
  }
}

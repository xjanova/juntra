import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/account_repository.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/widgets/account_feature_page.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AccountFeaturePage<CardCollection>(
    title: 'สมุดสะสมไพ่', feature: 'collection', value: ref.watch(collectionProvider),
    onRetry: () => ref.invalidate(collectionProvider),
    builder: (collection) => RefreshIndicator(
      onRefresh: () async { ref.invalidate(collectionProvider); await ref.read(collectionProvider.future); },
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('พบแล้ว ${collection.found} / ${collection.total} ใบ', style: baiJamjuree(size: 22)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: collection.total > 0
              ? (collection.found / collection.total).clamp(0, 1) : 0),
            if (collection.favourite case final favourite?) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('ไพ่ที่พบมากที่สุด · ${favourite['name_th']} (${favourite['count']} ครั้ง)')),
          ]))),
        SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150, childAspectRatio: .47, crossAxisSpacing: 12, mainAxisSpacing: 16),
            itemCount: collection.cards.length,
            itemBuilder: (_, i) => _Card(card: collection.cards[i]),
          )),
      ]),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.card});
  final CollectionCard card;
  @override
  Widget build(BuildContext context) {
    Widget back() => Image.asset(JuntraArt.cardBack, fit: BoxFit.contain);
    return Semantics(label: '${card.name} ${card.found ? '${card.count} ครั้ง' : 'ยังไม่พบ'}',
      child: Column(children: [
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child:
          card.found && card.imageUrl != null ? CachedNetworkImage(imageUrl: card.imageUrl!,
            fit: BoxFit.contain, placeholder: (_, _) => back(), errorWidget: (_, _, _) => back()) : back())),
        const SizedBox(height: 6),
        Text(card.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12)),
        Text(card.found ? '${card.count} ครั้ง · กลับหัว ${card.reversedCount}' : 'ยังไม่พบ',
          style: const TextStyle(fontSize: 10, color: JuntraColors.textMuted)),
      ]));
  }
}

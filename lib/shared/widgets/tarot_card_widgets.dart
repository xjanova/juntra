import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../data/tarot_deck.dart';

/// The mystical face-down back of a tarot card — purple/gold filigree
/// pattern, used during the cinematic shuffle phase.
class CardBack extends StatelessWidget {
  const CardBack({super.key, this.width = 88, this.height = 145});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF2D1A5C), Color(0xFF1A0F2E), Color(0xFF0A0414)],
        ),
        borderRadius: BorderRadius.circular(width * 0.08),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.55), width: 1.4),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), blurRadius: 18, offset: Offset(0, 8)),
          BoxShadow(color: Color(0x33F0C75E), blurRadius: 24, spreadRadius: -4),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.08 - 1.4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Inner double border
            Padding(
              padding: const EdgeInsets.all(6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: JuntraColors.gold.withValues(alpha: 0.35), width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(width * 0.06),
                ),
              ),
            ),
            // Centerpiece glyph
            Container(
              width: width * 0.42, height: width * 0.42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    JuntraColors.gold.withValues(alpha: 0.4),
                    JuntraColors.gold.withValues(alpha: 0.0),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '☾',
                style: TextStyle(
                  fontSize: width * 0.32,
                  color: JuntraColors.goldLight,
                  height: 1.0,
                ),
              ),
            ),
            // Corner ornaments
            ..._corners(width),
          ],
        ),
      ),
    );
  }

  List<Widget> _corners(double w) {
    return [
      Positioned(top: 6, left: 6, child: _ornament(w)),
      Positioned(top: 6, right: 6, child: _ornament(w)),
      Positioned(bottom: 6, left: 6, child: _ornament(w)),
      Positioned(bottom: 6, right: 6, child: _ornament(w)),
    ];
  }

  Widget _ornament(double w) => Text(
        '✦',
        style: TextStyle(
          fontSize: w * 0.10,
          color: JuntraColors.gold.withValues(alpha: 0.7),
          height: 1.0,
        ),
      );
}

/// Face-up tarot card — Roman numeral, Thai name, English subtitle,
/// element glyph at center on a deep purple ground.
class CardFront extends StatelessWidget {
  const CardFront({
    super.key,
    required this.card,
    this.width = 88,
    this.height = 145,
    this.reversed = false,
  });
  final TarotCard card;
  final double width;
  final double height;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF6E0), Color(0xFFEBD7A0), Color(0xFFC9A85E)],
        ),
        borderRadius: BorderRadius.circular(width * 0.08),
        border: Border.all(color: JuntraColors.goldDark, width: 1.6),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      padding: EdgeInsets.all(width * 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            card.symbol,
            style: GoogleFonts.cinzel(
              fontSize: width * 0.16,
              fontWeight: FontWeight.w700,
              color: JuntraColors.goldDark,
              letterSpacing: 1.4,
            ),
          ),
          Text(
            card.element,
            style: TextStyle(
              fontSize: width * 0.42,
              color: JuntraColors.bgPurpleDeep,
              height: 1.0,
            ),
          ),
          Column(
            children: [
              Text(
                card.thai,
                style: GoogleFonts.baiJamjuree(
                  textStyle: TextStyle(
                    fontSize: width * 0.13,
                    fontWeight: FontWeight.w700,
                    color: JuntraColors.bgPurpleDeep,
                    height: 1.1,
                  ),
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                card.name,
                style: GoogleFonts.cinzel(
                  fontSize: width * 0.085,
                  color: JuntraColors.goldDark,
                  letterSpacing: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );

    return reversed
        ? Transform.rotate(angle: 3.14159, child: body)
        : body;
  }
}

/// Face-up tarot card that PREFERS the real web art (Rider-Waite served from
/// จันทรา.online) and falls back to the built-in [CardFront] drawing when no
/// [imageUrl] is given, while the image is still loading, or if it fails to
/// load (offline / 404). This is the widget the seeker sees on reveal + in
/// the reading result — the local drawing is only ever the safety net.
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    this.imageUrl,
    this.width = 88,
    this.height = 145,
    this.reversed = false,
  });

  final TarotCard card;
  final String? imageUrl;
  final double width;
  final double height;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    // Built-in drawing (no internal rotation — CardFace rotates the whole
    // widget below so the image + fallback flip identically).
    final fallback = CardFront(card: card, width: width, height: height);

    final url = imageUrl;
    final Widget face;
    if (url == null || url.isEmpty) {
      face = fallback;
    } else {
      // Match CardFront's gold frame + drop shadow so a real photo and the
      // drawn fallback sit in the same deck without a visible seam.
      face = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.08),
          border: Border.all(color: JuntraColors.goldDark, width: 1.6),
          boxShadow: const [
            BoxShadow(color: Color(0xCC000000), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(width * 0.08 - 1.6),
          child: CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 250),
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
          ),
        ),
      );
    }

    return reversed
        ? Transform.rotate(angle: math.pi, child: face)
        : face;
  }
}

/// Face-down card that prefers the operator's web card-back (from
/// `card_back_url`) and falls back to the built-in [CardBack] filigree.
/// Used for the prominent hero backs (travel stack + reveal flip-side);
/// the lightweight [CardBack] still draws the dense 78-card fan for speed.
class CardBackFace extends StatelessWidget {
  const CardBackFace({
    super.key,
    this.imageUrl,
    this.width = 88,
    this.height = 145,
  });

  final String? imageUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fallback = CardBack(width: width, height: height);
    final url = imageUrl;
    if (url == null || url.isEmpty) return fallback;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.08),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.55), width: 1.4),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.08 - 1.4),
        child: CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, _) => fallback,
          errorWidget: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

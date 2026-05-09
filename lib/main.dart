import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/sound/sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Thai locale data BEFORE the first frame, otherwise
  // DateFormat('EEEE', 'th') in HomeScreen throws LocaleDataException
  // and the entire MaterialApp.builder fails — which in release mode
  // shows as a black screen with no error UI. Splash didn't crash
  // because it doesn't format any locale-dependent dates.
  await initializeDateFormatting('th_TH', null);

  // Lock to portrait — the app is a vertical mobile experience by design
  // (cinematic shuffle game and natal chart wheel are both portrait-tuned).
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  // Edge-to-edge with light status/navigation icons against the night-sky
  // background (#000 → #1A0F2E radial).
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF000000),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Pre-load mystical SFX (shuffle / pick / reveal / complete) so the first
  // tap in the cinematic shuffle plays without a load-stutter. Async, fire
  // and forget — SoundService.play() no-ops gracefully if init isn't done
  // yet, so we don't block first paint on the audio backend.
  unawaited(SoundService.instance.init());

  runApp(const ProviderScope(child: JuntraApp()));
}

// GENERATED from tokens/tokens.json (sha256 86c872ea58c6). Do not edit by hand: change the source and run `npm run build`.
import 'package:flutter/material.dart';

/// Colours. Callout names keep the app's existing call* spellings.
class TokenColors {
  static const bg = Color(0xFF0D1117);
  static const bgRaised = Color(0xFF0F1318);
  static const panel = Color(0xFF161B22);
  static const panelHover = Color(0xFF1B271E);
  static const surface = Color(0xFF21262D);
  static const border = Color(0xFF30363D);
  static const borderMid = Color(0xFF3D4450);
  static const text = Color(0xFFE6EDF3);
  static const text2 = Color(0xFFB1BAC4);
  static const text3 = Color(0xFF7D8590);
  static const textInverse = Color(0xFF0D1117);
  static const green = Color(0xFF3FB950);
  static const greenBright = Color(0xFF56D364);
  static const greenDim = Color(0xFF238636);
  static const greenHover = Color(0xFF2EA043);
  static const greenBg = Color(0x1A3FB950);
  static const greenBg2 = Color(0x0F3FB950);
  static const greenGlow = Color(0x593FB950);
  static const amber = Color(0xFFD29922);
  static const amberBg = Color(0x1FD29922);
  static const red = Color(0xFFF85149);
  static const redBg = Color(0x1FF85149);
  static const cyan = Color(0xFF58A6FF);
  static const cyanBg = Color(0x1A58A6FF);
  static const blue = TokenColors.cyan;
  static const violet = Color(0xFFBC8CFF);
  static const violetBg = Color(0x1ABC8CFF);
  static const callWatch = Color(0xFFD9A259);
  static const callWatchBg = Color(0x17D9A259);
  static const callJargon = Color(0xFF8AA9D9);
  static const callJargonBg = Color(0x178AA9D9);
  static const callBook = Color(0xFFA892D9);
  static const callBookBg = Color(0x17A892D9);
  static const callQuote = Color(0xFFD98A4F);
  static const callQuoteBg = Color(0x14D98A4F);
  static const callResearch = Color(0xFF6EA6D9);
  static const callResearchBg = Color(0x1A6EA6D9);
  static const callFact = Color(0xFFD9C15C);
  static const callFactBg = Color(0x1AD9C15C);
  static const callQuiz = Color(0xFF4FB0A5);
  static const callQuizBg = Color(0x1A4FB0A5);
  static const callLearn = TokenColors.green;
  static const callLearnBg = Color(0x1A3FB950);
}

class TokenFonts {
  static const ui = 'Inter';
  static const mono = 'JetBrains Mono';
}

class TokenWeights {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const black = FontWeight.w900;
}

class TokenSize {
  static const rSm = 5.0;
  static const rMd = 10.0;
  static const rLg = 12.0;
  static const rXl = 16.0;
  static const pad = 14.0;
  static const gap = 10.0;
}

class TokenType {
  static const body = TextStyle(fontFamily: TokenFonts.ui, fontSize: 14.0, height: 1.5, color: TokenColors.text);
  static const body2 = TextStyle(fontFamily: TokenFonts.ui, fontSize: 13.0, height: 1.45, color: TokenColors.text2);
  static const small = TextStyle(fontFamily: TokenFonts.ui, fontSize: 12.0, height: 1.4, color: TokenColors.text2);
  static const tiny = TextStyle(fontFamily: TokenFonts.ui, fontSize: 11.0, height: 1.3, color: TokenColors.text3);
  static const label = TextStyle(fontFamily: TokenFonts.ui, fontSize: 10.5, height: 1.2, color: TokenColors.text3, fontWeight: TokenWeights.semibold, letterSpacing: 1.2);
  static const title = TextStyle(fontFamily: TokenFonts.ui, fontSize: 16.0, height: 1.3, color: TokenColors.text, fontWeight: TokenWeights.semibold, letterSpacing: -0.2);
  static const headline = TextStyle(fontFamily: TokenFonts.ui, fontSize: 19.0, height: 1.25, color: TokenColors.text, fontWeight: TokenWeights.bold, letterSpacing: -0.4);
  static const mono = TextStyle(fontFamily: TokenFonts.mono, fontSize: 11.5, height: 1.45, color: TokenColors.text2);
  static const monoSmall = TextStyle(fontFamily: TokenFonts.mono, fontSize: 10.0, height: 1.35, color: TokenColors.text3);
  static const idBadge = TextStyle(fontFamily: TokenFonts.mono, fontSize: 10.5, height: 1.2, color: TokenColors.green, fontWeight: TokenWeights.medium);
}

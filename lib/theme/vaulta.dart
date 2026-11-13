import 'package:flutter/material.dart';

/// Vaulta 디자인 토큰 (DESIGN.md §2-§5).
/// 이미지에서 추출한 다크 네이비 + 스카이 블루 팔레트.
abstract final class Vaulta {
  // ── Dark ──────────────────────────────────────────────
  static const bg = Color(0xFF050B18);
  static const surface = Color(0xFF0C162E);
  static const surfaceElevated = Color(0xFF12203C);
  static const accent = Color(0xFF2E7CF6);
  static const accentBright = Color(0xFF55A9FF);
  static const accentDeep = Color(0xFF1B4FD8);
  static const actionCircle = Color(0xFF1E6FF2);
  static const mint = Color(0xFF7EF0C4);
  static const success = Color(0xFF34D17B);
  static const warning = Color(0xFFFF9F43);
  static const danger = Color(0xFFFF5C6C);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9AA6C2);
  static const textMuted = Color(0xFF5A6B8C);
  static const stroke = Color(0x14FFFFFF);
  static const heroLabel = Color(0xB3FFFFFF);

  /// 앱 기본 폰트 패밀리. 버튼 textStyle을 덮어쓸 때는 반드시 함께 지정한다.
  /// (지정하지 않으면 Material 기본값이 아닌 폴백 폰트로 렌더링된다)
  static const fontFamily = 'Roboto';

  // ── Light ─────────────────────────────────────────────
  static const lightBg = Color(0xFFEEF3FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF0B1526);
  static const lightTextSecondary = Color(0xFF5B6B8C);
  static const lightStroke = Color(0x140B1526);

  // ── Shape ─────────────────────────────────────────────
  static const radiusCard = 20.0;
  static const radiusHero = 26.0;
  static const radiusInput = 16.0;
  static const radiusChip = 12.0;

  // ── Gradients ─────────────────────────────────────────
  static const heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF4DA6FF), accentDeep],
  );
  static const progressGradient = LinearGradient(colors: [accent, mint]);

  /// 히어로 카드 상단 글로우.
  static const heroGlow = RadialGradient(
    center: Alignment(0.5, -0.6),
    radius: 1.2,
    colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
  );

  // ── Theme ─────────────────────────────────────────────
  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: dark ? accent : actionCircle,
      brightness: brightness,
      surface: dark ? surface : lightSurface,
    );
    final textTheme = Typography.whiteMountainView.apply(
      bodyColor: dark ? textPrimary : lightTextPrimary,
      displayColor: dark ? textPrimary : lightTextPrimary,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? bg : lightBg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? bg : lightBg,
        foregroundColor: dark ? textPrimary : lightTextPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: dark ? textPrimary : lightTextPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: dark ? surface : lightSurface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: dark ? stroke : lightStroke),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? surfaceElevated : lightSurface,
        hintStyle: TextStyle(color: dark ? textMuted : lightTextSecondary),
        prefixIconColor: dark ? textMuted : lightTextSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(color: dark ? stroke : lightStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: actionCircle,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentBright),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? textPrimary : lightTextPrimary,
          shape: const StadiumBorder(),
          side: BorderSide(color: dark ? stroke : lightStroke, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? actionCircle : null,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusChip),
          side: BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? surfaceElevated : lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? surfaceElevated : lightTextPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusChip),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? stroke : lightStroke,
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: Color(0x1EFFFFFF),
      ),
    );
  }
}

/// 상태 알약 배지 (연결됨/미연결/USB).
class VaultaStatusPill extends StatelessWidget {
  const VaultaStatusPill._(this.label, this.color);
  factory VaultaStatusPill.connected() =>
      const VaultaStatusPill._('연결됨', Vaulta.success);
  factory VaultaStatusPill.disconnected() =>
      const VaultaStatusPill._('미연결', Vaulta.danger);
  factory VaultaStatusPill.usb() =>
      const VaultaStatusPill._('USB', Vaulta.warning);
  factory VaultaStatusPill.live() =>
      const VaultaStatusPill._('실시간', Vaulta.success);
  factory VaultaStatusPill.paused() =>
      const VaultaStatusPill._('일시정지', Vaulta.warning);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vaulta 파란 원형 리스트 아이콘.
class VaultaListIcon extends StatelessWidget {
  const VaultaListIcon(this.icon, {super.key});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: const BoxDecoration(
      color: Vaulta.actionCircle,
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: Colors.white, size: 20),
  );
}

/// 중앙 정렬 최대폭 컨테이너 (데스크톱 설정/도구 화면용).
class VaultaPageWidth extends StatelessWidget {
  const VaultaPageWidth({super.key, required this.child, this.maxWidth = 760});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Vaulta 섹션 타이틀 (16px/700).
class VaultaSectionTitle extends StatelessWidget {
  const VaultaSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: dark ? Vaulta.textPrimary : Vaulta.lightTextPrimary,
        ),
      ),
    );
  }
}

/// Vaulta 그러데이션 확정형 진행 바 (DESIGN.md §3).
class VaultaProgressBar extends StatelessWidget {
  const VaultaProgressBar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 8,
        color: dark
            ? Colors.white.withValues(alpha: 0.12)
            : Vaulta.lightTextPrimary.withValues(alpha: 0.12),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: const BoxDecoration(gradient: Vaulta.progressGradient),
          ),
        ),
      ),
    );
  }
}

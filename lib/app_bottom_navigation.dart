import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_glass.dart';

/// 底部导航。可选悬浮胶囊 + 毛玻璃/液态玻璃外观；
/// 选中项使用圆形高亮（HyperOS 风格），不再使用顶部横条。
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.floating = false,
    this.blurred = false,
    this.liquidGlass = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  /// 类 Apple 的悬浮胶囊底栏。
  final bool floating;

  /// 底栏背景模糊（需要 Scaffold 开启 extendBody 才能看到内容）。
  final bool blurred;

  /// 液态玻璃：SukiSU-Ultra 风格的透镜折射玻璃（见 [LiquidGlassStyle]）。
  final bool liquidGlass;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    // 着色器异步就绪后重建，从回退外观切换到液态玻璃。
    valueListenable: LiquidGlassShaders.ready,
    builder: (context, _, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // 液态玻璃需要透镜着色器；不可用时回退纯 Flutter 毛玻璃外观。
    final useLiquidGlass =
        liquidGlass && floating && LiquidGlassShaders.available;
    final glass = useLiquidGlass || blurred;
    final radius = floating ? 30.0 : 0.0;

    Widget bar = Row(
      children: [
        for (final (index, destination) in destinations.indexed)
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              selected: index == selectedIndex,
              child: Tooltip(
                message: destination.label,
                excludeFromSemantics: true,
                child: InkWell(
                  key: ValueKey('bottom-nav-$index'),
                  borderRadius: BorderRadius.circular(radius > 0 ? 20 : 0),
                  onTap: () => onDestinationSelected(index),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: floating ? 70 : 68,
                      minWidth: 48,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: floating ? 9 : 9,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 选中项：图标外的浅色圆形高亮（HyperOS 风格）。
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              // 液态玻璃的选中 pill 已承担高亮职责。
                              color:
                                  index == selectedIndex && !useLiquidGlass
                                  ? colors.primary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: IconTheme(
                              data: IconThemeData(
                                size: 22,
                                color: index == selectedIndex
                                    ? colors.primary
                                    : colors.onSurface.withValues(alpha: 0.78),
                              ),
                              child: index == selectedIndex
                                  ? destination.selectedIcon ??
                                        destination.icon
                                  : destination.icon,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            destination.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.15,
                              letterSpacing: 0.2,
                              fontWeight: index == selectedIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: index == selectedIndex
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (useLiquidGlass) {
      return _buildLiquidGlass(context, theme, colors, bar);
    }

    if (glass) {
      bar = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        // 性能：单层 blur（compose 的 ColorFilter 会额外强制一层 saveLayer，
        // 且模糊成本近似随 sigma 平方增长；sigma 20 与 32 视觉差异很小）。
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: liquidGlass ? 20 : 12,
            sigmaY: liquidGlass ? 20 : 12,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surface.withValues(alpha: liquidGlass ? 0.30 : 0.72),
                  colors.surface.withValues(alpha: liquidGlass ? 0.14 : 0.60),
                ],
              ),
            ),
            child: RepaintBoundary(child: bar),
          ),
        ),
      );
    }

    if (floating) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
          ),
          foregroundDecoration: liquidGlass
              ? BoxDecoration(
                  // 液态玻璃高光：顶部亮、中部透明、底部微亮的渐变 + 亮边。
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.38),
                      Colors.white.withValues(alpha: 0.02),
                      Colors.white.withValues(alpha: 0.14),
                    ],
                    stops: const [0, 0.42, 1],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                )
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: liquidGlass
                    ? Colors.white.withValues(alpha: 0.0)
                    : colors.outlineVariant.withValues(alpha: 0.6),
                width: liquidGlass ? 0 : .5,
              ),
              color: glass ? Colors.transparent : colors.surface,
            ),
            child: bar,
          ),
        ),
      );
    }

    return Material(
      color: glass ? Colors.transparent : theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: glass
                    ? colors.outlineVariant.withValues(alpha: 0.4)
                    : colors.outlineVariant,
                width: .5,
              ),
            ),
          ),
          child: bar,
        ),
      ),
    );
  }

  /// 液态玻璃底栏：SukiSU-Ultra `FloatingBottomBar` 视觉的 Flutter 移植。
  ///
  /// 玻璃面区域相对胶囊形外扩 [LiquidGlassStyle.padding]，为透镜折射提供
  /// 可采样的真实背景；形状之外由透镜着色器裁掉（输出全透明）。
  Widget _buildLiquidGlass(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    Widget bar,
  ) {
    const barHeight = 70.0;
    const barRadius = 30.0;
    const pillHeight = 56.0;
    const style = LiquidGlassStyle.bar;
    final isDark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: SizedBox(
        height: barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barSize = Size(constraints.maxWidth, barHeight);
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                // 玻璃面：折射背后内容（vibrancy + 模糊 + 透镜）。
                Positioned(
                  left: -style.padding,
                  right: -style.padding,
                  top: -style.padding,
                  bottom: -style.padding,
                  child: IgnorePointer(
                    child: LiquidGlassSurface(
                      slot: 'bar',
                      style: style,
                      shapeSize: barSize,
                    ),
                  ),
                ),
                // 容器色与投影（SukiSU：surfaceContainer @ 0.4 + dropShadow）。
                Positioned.fill(
                  child: IgnorePointer(
                    child: GlassTint(
                      size: barSize,
                      radius: barRadius,
                      color: colors.surfaceContainer.withValues(alpha: 0.4),
                      shadowColor: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.1,
                      ),
                    ),
                  ),
                ),
                // 轮廓高光（SukiSU：BloomStroke，光源位于左侧）。
                Positioned.fill(
                  child: IgnorePointer(
                    child: GlassRimHighlight(
                      size: barSize,
                      radius: barRadius,
                      lightDirection: const Offset(-1, 0),
                      alpha: 0.6,
                    ),
                  ),
                ),
                // 选中项玻璃 pill，位于内容之下。
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, pillConstraints) {
                      final tabWidth =
                          pillConstraints.maxWidth / destinations.length;
                      final pillWidth = tabWidth - 4;
                      if (pillWidth <= 0) return const SizedBox.shrink();
                      return Stack(
                        children: [
                          Positioned(
                            left: selectedIndex * tabWidth + 2,
                            top: (barHeight - pillHeight) / 2,
                            width: pillWidth,
                            height: pillHeight,
                            child: IgnorePointer(
                              child: LiquidGlassPill(
                                size: Size(pillWidth, pillHeight),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Positioned.fill(child: bar),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 液态玻璃（liquid glass）效果。
///
/// 视觉算法移植自 SukiSU-Ultra（https://github.com/ShirkNeko/SukiSU-Ultra ，
/// GPL-3.0-or-later）的 `ui/component/liquid`（Lens.kt / Vibrancy.kt /
/// InnerShadow.kt）与 `ui/component/FloatingBottomBar.kt`，其上游为
/// Kyant0/AndroidLiquidGlass（https://github.com/Kyant0/AndroidLiquidGlass ，
/// Apache-2.0）。要点：
///
/// - 玻璃面：对背后内容做饱和度提升（vibrancy，1.5 倍）+ 轻度模糊 +
///   沿圆角矩形边缘带的透镜折射（lens，由 [LiquidGlassSurface] 经
///   `BackdropFilter` + `ImageFilter.shader` 完成）；
/// - 容器色：`surfaceContainer` @ 0.4 罩在折射面之上；
/// - 轮廓高光：沿轮廓的方向光描边（BloomStroke 的简化移植，
///   [GlassRimHighlight]）；
/// - 选中项：独立的玻璃 pill，带深度折射、色散与内阴影
///   （[LiquidGlassPill]）。
///
/// 着色器的滤镜输入纹理恒为整屏快照，形状在屏幕中的位置由
/// [LiquidGlassSurface] 布局后经 `localToGlobal` 取得并传入；形状之外的
/// 输出由着色器裁掉（全透明）。
///
/// 运行环境不支持 `ImageFilter.shader`（非 Impeller 后端）或着色器加载
/// 失败时，[LiquidGlassShaders.available] 为 false，调用方应回退到纯
/// Flutter 的毛玻璃外观。

/// 玻璃面的几何与折射参数（单位：逻辑像素）。
class LiquidGlassStyle {
  const LiquidGlassStyle({
    required this.cornerRadius,
    required this.refractionHeight,
    required this.refractionAmount,
    this.depthEffect = false,
    this.chromaticAberration = 0,
    this.vibrancy = true,
    this.blurRadius = 4,
  });

  /// 圆角半径。
  final double cornerRadius;

  /// 折射作用的边缘带宽度。
  final double refractionHeight;

  /// 折射位移量。
  final double refractionAmount;

  /// 深度折射：折射方向额外向形状中心牵引。
  final bool depthEffect;

  /// 色散强度，0 为关闭。
  final double chromaticAberration;

  /// 是否将背景饱和度提升至 1.5 倍。
  final bool vibrancy;

  /// 背景模糊半径。
  final double blurRadius;

  /// 底栏玻璃面（SukiSU `FloatingBottomBar` 基础层参数）。
  static const bar = LiquidGlassStyle(
    cornerRadius: 30,
    refractionHeight: 24,
    refractionAmount: 24,
  );

  /// 顶栏玻璃面：通栏直角（贴屏幕顶边），折射参数与底栏一致。
  static const top = LiquidGlassStyle(
    cornerRadius: 0,
    refractionHeight: 24,
    refractionAmount: 24,
  );

  /// 选中项玻璃 pill（SukiSU 拖动 pill 参数，取稳态值）。
  static const pill = LiquidGlassStyle(
    cornerRadius: 28,
    refractionHeight: 10,
    refractionAmount: 14,
    depthEffect: true,
    chromaticAberration: 0.5,
  );
}

/// 透镜着色器的加载与 uniform 管理。
///
/// `ImageFilter.shader()` 在创建时会快照 uniform（引擎侧 `as_image_filter`
/// 显式拷贝），因此 uniform 变化后必须重建 [ui.ImageFilter]；这里按
/// 「样式 + 形状尺寸 + 形状中心（屏幕坐标）+ 像素比」缓存，稳态场景零分配。
class LiquidGlassShaders {
  LiquidGlassShaders._();

  static const _shaderAsset = 'shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;

  /// 着色器就绪通知：加载完成或确认不可用后自增，用于触发界面重建。
  static final ValueNotifier<int> ready = ValueNotifier<int>(0);

  /// 着色器是否可用（已成功加载）。
  static bool get available => _program != null;

  static final Map<String, _CachedFilter> _cache = {};

  /// 取得 [slot]（'bar' / 'pill'）对应的滤镜；不可用时返回 null。
  ///
  /// [shapeCenter] 为形状中心在根视图（屏幕）坐标系中的逻辑像素位置——
  /// BackdropFilter 的滤镜输入纹理恒为整屏快照，着色器据此定位形状。
  static ui.ImageFilter? filterFor(
    String slot,
    LiquidGlassStyle style,
    Size shapeSize,
    Offset shapeCenter,
    double dpr,
  ) {
    final program = _program;
    if (program == null) return null;
    final key =
        '${style.cornerRadius}|${style.refractionHeight}'
        '|${style.refractionAmount}|${style.depthEffect}'
        '|${style.chromaticAberration}|${style.vibrancy}'
        '|${style.blurRadius}'
        '|${shapeSize.width}x${shapeSize.height}'
        '|${shapeCenter.dx}x${shapeCenter.dy}|$dpr';
    final cached = _cache[slot];
    if (cached != null && cached.key == key) return cached.filter;

    final shader = program.fragmentShader();
    try {
      void set(String name, double value) =>
          shader.getUniformFloat(name).set(value);
      void set2(String name, double x, double y) {
        shader.getUniformFloat(name, 0).set(x);
        shader.getUniformFloat(name, 1).set(y);
      }

      set2('u_shape_center', shapeCenter.dx * dpr, shapeCenter.dy * dpr);
      set2('u_shape_size', shapeSize.width * dpr, shapeSize.height * dpr);
      final r = style.cornerRadius * dpr;
      for (var i = 0; i < 4; i++) {
        shader.getUniformFloat('u_corner_radii', i).set(r);
      }
      set('u_refraction_height', style.refractionHeight * dpr);
      set('u_refraction_amount', style.refractionAmount * dpr);
      set('u_depth_effect', style.depthEffect ? 1 : 0);
      set('u_chromatic_aberration', style.chromaticAberration);
      set('u_vibrancy', style.vibrancy ? 1 : 0);
      set('u_blur_radius', style.blurRadius * dpr);
      final filter = ui.ImageFilter.shader(shader);
      _cache[slot] = _CachedFilter(key, filter);
      return filter;
    } catch (_) {
      // uniform 名称/布局不匹配或着色器不满足 ImageFilter.shader 约束：
      // 放弃着色器路径，回退纯 Flutter 外观。
      return null;
    }
  }

  /// 启动时预加载；重复调用安全。
  static Future<void> ensureLoaded() async {
    if (_program != null) return;
    if (!ui.ImageFilter.isShaderFilterSupported) {
      ready.value++;
      return;
    }
    try {
      _program = await ui.FragmentProgram.fromAsset(_shaderAsset);
    } catch (_) {
      _program = null;
    }
    ready.value++;
  }
}

class _CachedFilter {
  _CachedFilter(this.key, this.filter);

  final String key;
  final ui.ImageFilter filter;
}

/// 一片液态玻璃：对背后内容做折射，形状为以 [shapeSize] 为中心（屏幕坐标）
/// 的圆角矩形。
///
/// 本组件不绘制任何前景，容器色、高光、内容由调用方叠加在其上。
///
/// 实现要点：`BackdropFilter` + `ImageFilter.shader` 的滤镜输入纹理恒为整屏
/// 快照（引擎 `Canvas::SaveLayer` 对 backdrop filter 的 save layer 做
/// flood_input_coverage），着色器的 `FlutterFragCoord()` 即屏幕像素坐标。
/// 因此形状中心必须由本组件在布局完成后经 `localToGlobal` 取得并传入着色器
/// （见 [LiquidGlassShaders.filterFor]）；首帧位置未知时不渲染，避免玻璃
/// 闪现在错误位置。
class LiquidGlassSurface extends StatefulWidget {
  const LiquidGlassSurface({
    super.key,
    required this.slot,
    required this.style,
    required this.shapeSize,
  });

  final String slot;
  final LiquidGlassStyle style;
  final Size shapeSize;

  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
  /// 形状中心在根视图（屏幕）坐标系中的逻辑像素位置。
  Offset? _shapeCenter;

  @override
  void initState() {
    super.initState();
    // 首帧布局完成后取位置，并持续监听布局变化（键盘、旋转等）。
    _schedulePositionUpdate();
  }

  void _schedulePositionUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.size != Size.zero) {
        final center = box.localToGlobal(box.size.center(Offset.zero));
        if (_shapeCenter != center) {
          setState(() => _shapeCenter = center);
        }
      }
      // 位置可能随布局变化而改变；每帧复检（仅在变化时 setState）。
      _schedulePositionUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final center = _shapeCenter;
    if (center == null) return const SizedBox.shrink();
    final filter = LiquidGlassShaders.filterFor(
      widget.slot,
      widget.style,
      widget.shapeSize,
      center,
      MediaQuery.devicePixelRatioOf(context),
    );
    if (filter == null) return const SizedBox.shrink();
    return SizedBox(
      width: widget.shapeSize.width,
      height: widget.shapeSize.height,
      child: BackdropFilter(
        filter: filter,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 玻璃容器色（SukiSU 的 `surfaceContainer @ 0.4`），裁剪在形状内。
class GlassTint extends StatelessWidget {
  const GlassTint({
    super.key,
    required this.size,
    required this.radius,
    required this.color,
    this.shadowColor,
  });

  final Size size;
  final double radius;
  final Color color;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size.width,
    height: size.height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: color,
        boxShadow: shadowColor == null
            ? null
            : [BoxShadow(color: shadowColor!, blurRadius: 10)],
      ),
    ),
  );
}

/// 沿轮廓的方向光高光描边：BloomStroke（主光 + 次光、双峰）的简化移植。
class GlassRimHighlight extends StatelessWidget {
  const GlassRimHighlight({
    super.key,
    required this.size,
    required this.radius,
    required this.lightDirection,
    this.alpha = 0.75,
    this.secondaryAlpha = 0.3,
  });

  final Size size;
  final double radius;

  /// 指向光源的单位向量，如 `Offset(-1, 0)` 表示光在左侧。
  final Offset lightDirection;
  final double alpha;
  final double secondaryAlpha;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size.width,
    height: size.height,
    child: CustomPaint(
      painter: _RimHighlightPainter(
        radius: radius,
        lightDirection: lightDirection,
        alpha: alpha,
        secondaryAlpha: secondaryAlpha,
      ),
    ),
  );
}

class _RimHighlightPainter extends CustomPainter {
  _RimHighlightPainter({
    required this.radius,
    required this.lightDirection,
    required this.alpha,
    required this.secondaryAlpha,
  });

  final double radius;
  final Offset lightDirection;
  final double alpha;
  final double secondaryAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final center = rect.center;
    final half = rect.longestSide;

    // 主光：亮边贴在受光一侧，向对侧衰减。
    final lightSide = center + lightDirection * half;
    final darkSide = center - lightDirection * half;
    final primary = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(lightSide, darkSide, [
        Colors.white.withValues(alpha: alpha),
        Colors.white.withValues(alpha: alpha * 0.12),
      ]);
    canvas.drawRRect(rrect, primary);

    // 次光：自底部向上的柔光（SukiSU secondaryLight 位于底部）。
    final bottom = center + const Offset(0, 1) * half;
    final top = center - const Offset(0, 1) * half;
    final secondary = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 2)
      ..shader = ui.Gradient.linear(bottom, top, [
        Colors.white.withValues(alpha: secondaryAlpha),
        Colors.white.withValues(alpha: 0),
      ]);
    canvas.drawRRect(rrect, secondary);
  }

  @override
  bool shouldRepaint(_RimHighlightPainter old) =>
      old.radius != radius ||
      old.lightDirection != lightDirection ||
      old.alpha != alpha ||
      old.secondaryAlpha != secondaryAlpha;
}

/// 形状内侧的柔和阴影：SukiSU `InnerShadow`（偏移 + 高斯模糊 + 反相裁剪）的移植。
class GlassInnerShadow extends StatelessWidget {
  const GlassInnerShadow({
    super.key,
    required this.size,
    required this.radius,
    this.offset = const Offset(0, 8),
    this.color = const Color(0x26000000),
  });

  final Size size;
  final double radius;
  final Offset offset;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size.width,
    height: size.height,
    child: CustomPaint(
      painter: _InnerShadowPainter(
        radius: radius,
        offset: offset,
        color: color,
      ),
    ),
  );
}

class _InnerShadowPainter extends CustomPainter {
  _InnerShadowPainter({
    required this.radius,
    required this.offset,
    required this.color,
  });

  final double radius;
  final Offset offset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.clipPath(path);
    canvas.drawPath(
      path.shift(offset),
      Paint()
        ..color = color
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerShadowPainter old) =>
      old.radius != radius || old.offset != offset || old.color != color;
}

/// 选中项的液态玻璃 pill：深度折射 + 色散透镜 + 容器色 + 内阴影 + 右侧高光。
class LiquidGlassPill extends StatelessWidget {
  const LiquidGlassPill({super.key, required this.size, this.tint});

  final Size size;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const style = LiquidGlassStyle.pill;
    final tintColor =
        tint ??
        (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.10));
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          LiquidGlassSurface(
            slot: 'pill',
            style: style,
            shapeSize: size,
          ),
          GlassTint(size: size, radius: style.cornerRadius, color: tintColor),
          GlassInnerShadow(
            size: size,
            radius: style.cornerRadius,
            offset: const Offset(0, 8),
            color: Colors.black.withValues(alpha: 0.15),
          ),
          GlassRimHighlight(
            size: size,
            radius: style.cornerRadius,
            // SukiSU 的 pill 高光光源位于右侧。
            lightDirection: const Offset(1, 0),
            alpha: 0.4,
          ),
        ],
      ),
    );
  }
}

/// 通栏液态玻璃面板（顶栏等场景）：透镜折射 + 容器色 + 可选底边发丝线。
///
/// 面板尺寸由布局约束决定；形状位置由 [LiquidGlassSurface] 自行定位。
class LiquidGlassPanel extends StatelessWidget {
  const LiquidGlassPanel({
    super.key,
    required this.style,
    required this.tint,
    this.slot = 'panel',
    this.bottomBorderColor,
  });

  final LiquidGlassStyle style;

  /// 容器色（罩在折射面之上）。
  final Color tint;

  /// 着色器缓存槽位标识。
  final String slot;

  /// 底边发丝线颜色（顶栏与内容的分界）。
  final Color? bottomBorderColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.isEmpty) return const SizedBox.shrink();
      return Stack(
        children: [
          Positioned.fill(
            child: LiquidGlassSurface(
              slot: slot,
              style: style,
              shapeSize: size,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint,
                border: bottomBorderColor == null
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: bottomBorderColor!,
                          width: 0.5,
                        ),
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

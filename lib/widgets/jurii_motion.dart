import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

abstract final class JuriiMotion {
  static const Duration press = Duration(milliseconds: 110);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve exitEase = Curves.easeInCubic;

  static bool disabled(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }
}

class JuriiPressable extends StatefulWidget {
  const JuriiPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.pressedScale = 0.985,
    this.semanticLabel,
    this.clipBehavior = Clip.hardEdge,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double pressedScale;
  final String? semanticLabel;
  final Clip clipBehavior;

  @override
  State<JuriiPressable> createState() => _JuriiPressableState();
}

class _JuriiPressableState extends State<JuriiPressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = JuriiMotion.disabled(context);
    final scale = _enabled && _pressed && !disabled ? widget.pressedScale : 1.0;

    return Semantics(
      button: _enabled,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: _enabled ? (_) => _setPressed(true) : null,
          onTapUp: _enabled ? (_) => _setPressed(false) : null,
          onTapCancel: _enabled ? () => _setPressed(false) : null,
          child: AnimatedScale(
            scale: scale,
            duration: disabled ? Duration.zero : JuriiMotion.press,
            curve: JuriiMotion.ease,
            child: widget.clipBehavior == Clip.none
                ? widget.child
                : ClipRRect(
                    borderRadius: widget.borderRadius,
                    clipBehavior: widget.clipBehavior,
                    child: widget.child,
                  ),
          ),
        ),
      ),
    );
  }
}

class JuriiFadeThroughSwitcher extends StatelessWidget {
  const JuriiFadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = JuriiMotion.standard,
    this.offset = const Offset(0, 0.025),
  });

  final Widget child;
  final Duration duration;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final disabled = JuriiMotion.disabled(context);

    return AnimatedSwitcher(
      duration: disabled ? Duration.zero : duration,
      switchInCurve: JuriiMotion.ease,
      switchOutCurve: JuriiMotion.exitEase,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: JuriiMotion.ease,
          reverseCurve: JuriiMotion.exitEase,
        );
        final position = Tween<Offset>(
          begin: offset,
          end: Offset.zero,
        ).animate(curved);

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: position, child: child),
        );
      },
      child: child,
    );
  }
}

class JuriiStaggeredItem extends StatelessWidget {
  const JuriiStaggeredItem({
    super.key,
    required this.index,
    required this.child,
    this.duration = JuriiMotion.standard,
    this.stepDelay = const Duration(milliseconds: 42),
    this.maxDelay = const Duration(milliseconds: 220),
    this.beginOffset = const Offset(0, 12),
  });

  final int index;
  final Widget child;
  final Duration duration;
  final Duration stepDelay;
  final Duration maxDelay;
  final Offset beginOffset;

  @override
  Widget build(BuildContext context) {
    if (JuriiMotion.disabled(context)) return child;

    final rawDelay = index * stepDelay.inMilliseconds;
    final delay = rawDelay > maxDelay.inMilliseconds
        ? maxDelay.inMilliseconds
        : rawDelay;
    final total = duration.inMilliseconds + delay;
    final delayRatio = total == 0 ? 0.0 : delay / total;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Curves.linear,
      builder: (context, value, animatedChild) {
        final shifted = delayRatio >= 1
            ? 1.0
            : ((value - delayRatio) / (1 - delayRatio)).clamp(0.0, 1.0);
        final eased = JuriiMotion.ease.transform(shifted.toDouble());

        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(
              beginOffset.dx * (1 - eased),
              beginOffset.dy * (1 - eased),
            ),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class JuriiPulse extends StatefulWidget {
  const JuriiPulse({
    super.key,
    required this.child,
    this.enabled = true,
    this.minScale = 0.94,
    this.maxScale = 1.08,
    this.duration = const Duration(milliseconds: 1300),
  });

  final Widget child;
  final bool enabled;
  final double minScale;
  final double maxScale;
  final Duration duration;

  @override
  State<JuriiPulse> createState() => _JuriiPulseState();
}

class _JuriiPulseState extends State<JuriiPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late Animation<double> _animation = _createAnimation();

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant JuriiPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.minScale != widget.minScale ||
        oldWidget.maxScale != widget.maxScale) {
      _animation = _createAnimation();
    }
    _syncController();
  }

  void _syncController() {
    if (widget.enabled) {
      if (!_controller.isAnimating) _controller.forward(from: 0);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  Animation<double> _createAnimation() {
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: widget.minScale,
          end: widget.maxScale,
        ).chain(CurveTween(curve: JuriiMotion.ease)),
        weight: 46,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: widget.maxScale,
          end: 1.0,
        ).chain(CurveTween(curve: JuriiMotion.ease)),
        weight: 54,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || JuriiMotion.disabled(context)) return widget.child;

    return ScaleTransition(scale: _animation, child: widget.child);
  }
}

class JuriiAnimatedCounter extends StatefulWidget {
  const JuriiAnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.duration = JuriiMotion.slow,
    this.format,
  });

  final int value;
  final TextStyle style;
  final Duration duration;
  final String Function(int value)? format;

  @override
  State<JuriiAnimatedCounter> createState() => _JuriiAnimatedCounterState();
}

class _JuriiAnimatedCounterState extends State<JuriiAnimatedCounter> {
  late int _beginValue;

  @override
  void initState() {
    super.initState();
    _beginValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant JuriiAnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _beginValue = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (JuriiMotion.disabled(context)) {
      return Text(
        widget.format?.call(widget.value) ?? '${widget.value}',
        style: widget.style,
      );
    }

    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _beginValue, end: widget.value),
      duration: _beginValue == widget.value ? Duration.zero : widget.duration,
      curve: JuriiMotion.ease,
      builder: (context, currentValue, _) {
        return Text(
          widget.format?.call(currentValue) ?? '$currentValue',
          style: widget.style,
        );
      },
    );
  }
}

class JuriiSkeletonList extends StatelessWidget {
  const JuriiSkeletonList({
    super.key,
    this.itemCount = 3,
    this.itemHeight = 84,
    this.gap = 12,
  });

  final int itemCount;
  final double itemHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < itemCount; index++) ...[
          JuriiSkeletonCard(height: itemHeight),
          if (index < itemCount - 1) SizedBox(height: gap),
        ],
      ],
    );
  }
}

class JuriiSkeletonCard extends StatefulWidget {
  const JuriiSkeletonCard({
    super.key,
    this.height = 84,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final double height;
  final BorderRadius borderRadius;

  @override
  State<JuriiSkeletonCard> createState() => _JuriiSkeletonCardState();
}

class _JuriiSkeletonCardState extends State<JuriiSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = JuriiMotion.disabled(context);

    if (disabled) {
      return _SkeletonSurface(
        height: widget.height,
        borderRadius: widget.borderRadius,
        alignment: const Alignment(-0.6, 0),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return _SkeletonSurface(
          height: widget.height,
          borderRadius: widget.borderRadius,
          alignment: Alignment((_controller.value * 2) - 1, 0),
        );
      },
    );
  }
}

class _SkeletonSurface extends StatelessWidget {
  const _SkeletonSurface({
    required this.height,
    required this.borderRadius,
    required this.alignment,
  });

  final double height;
  final BorderRadius borderRadius;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: colors.lightBlueBorder),
          gradient: LinearGradient(
            begin: Alignment(alignment.x - 1, -0.2),
            end: Alignment(alignment.x + 1, 0.2),
            colors: [
              colors.lightBlue.withValues(alpha: 0.68),
              colors.card,
              colors.lightBlue.withValues(alpha: 0.68),
            ],
            stops: const [0.18, 0.5, 0.82],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/professional_reach.dart';
import '../theme/app_colors.dart';
import 'jurii_motion.dart';

String _dataCurta(DateTime data) =>
    '${data.day.toString().padLeft(2, '0')}/'
    '${data.month.toString().padLeft(2, '0')}';

int _maiorAlcance(List<ReachDay> days) =>
    days.fold(0, (maior, dia) => dia.reach > maior ? dia.reach : maior);

class _RotuloDeData extends StatelessWidget {
  const _RotuloDeData({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: TextStyle(
        color: context.jColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Gráfico de área do alcance diário.
///
/// Desenhado à mão em vez de com biblioteca: são duas curvas e um degradê, e
/// uma dependência de gráfico traria mil opções que teriam que ser desligadas
/// uma a uma para caber na identidade do app. Aqui a curva usa os mesmos
/// tokens de cor e as mesmas durações do resto da interface.
class ReachChart extends StatelessWidget {
  const ReachChart({super.key, required this.days, this.height = 140});

  final List<ReachDay> days;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final semAnimacao = JuriiMotion.disabled(context);

    if (days.isEmpty) return SizedBox(height: height);

    final primeiro = days.first.day;
    final ultimo = days.last.day;

    return Semantics(
      // Curva desenhada não diz nada a leitor de tela. Sem este resumo, o
      // gráfico é um retângulo vazio para quem não enxerga.
      label:
          'Gráfico de alcance diário, de ${_dataCurta(primeiro)} '
          'a ${_dataCurta(ultimo)}. '
          'Maior alcance num dia: ${_maiorAlcance(days)} pessoas.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: ExcludeSemantics(
              child: _curva(context, colors, semAnimacao),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RotuloDeData(texto: _dataCurta(primeiro)),
              _RotuloDeData(texto: _dataCurta(ultimo)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _curva(BuildContext context, AppColors colors, bool semAnimacao) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: semAnimacao ? Duration.zero : JuriiMotion.slow,
        curve: JuriiMotion.ease,
        builder: (context, progresso, _) {
          return CustomPaint(
            painter: _ReachChartPainter(
              days: days,
              progress: progresso,
              lineColor: colors.primary,
              sponsoredColor: colors.accent,
              fillTop: colors.primary.withValues(alpha: 0.22),
              fillBottom: colors.primary.withValues(alpha: 0.02),
              gridColor: colors.divider,
            ),
          );
        },
      ),
    );
  }
}

class _ReachChartPainter extends CustomPainter {
  _ReachChartPainter({
    required this.days,
    required this.progress,
    required this.lineColor,
    required this.sponsoredColor,
    required this.fillTop,
    required this.fillBottom,
    required this.gridColor,
  });

  final List<ReachDay> days;

  /// 0 a 1: a curva é revelada da esquerda para a direita.
  final double progress;

  final Color lineColor;
  final Color sponsoredColor;
  final Color fillTop;
  final Color fillBottom;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty || size.width <= 0) return;

    // Escala com piso 1: uma série toda zerada dividiria por zero e, pior,
    // desenharia uma linha no topo dando a impressão de alcance cheio.
    final maximo = days
        .fold<int>(0, (maior, dia) => dia.reach > maior ? dia.reach : maior)
        .clamp(1, 1 << 30);

    final grade = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * (i / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grade);
    }

    Offset ponto(int indice, int valor) {
      final x = days.length == 1
          ? size.width / 2
          : size.width * (indice / (days.length - 1));
      final y = size.height - (valor / maximo) * size.height;
      return Offset(x, y);
    }

    // Revela por largura, não por opacidade: a curva "cresce" da esquerda para
    // a direita, que é como o tempo anda no gráfico.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));

    final curva = Path();
    for (var i = 0; i < days.length; i++) {
      final p = ponto(i, days[i].reach);
      if (i == 0) {
        curva.moveTo(p.dx, p.dy);
      } else {
        // Curva suave em vez de linha quebrada: ponto de controle no meio do
        // caminho horizontal, que é o traçado padrão de gráfico de série.
        final anterior = ponto(i - 1, days[i - 1].reach);
        final meio = (anterior.dx + p.dx) / 2;
        curva.cubicTo(meio, anterior.dy, meio, p.dy, p.dx, p.dy);
      }
    }

    final area = Path.from(curva)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillTop, fillBottom],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      curva,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Os dias com alcance patrocinado ganham um ponto dourado. É o que deixa
    // visível, sem texto nenhum, em que dias a vaga paga estava trabalhando.
    final marca = Paint()..color = sponsoredColor;
    for (var i = 0; i < days.length; i++) {
      if (days[i].sponsoredReach <= 0) continue;
      canvas.drawCircle(ponto(i, days[i].reach), 3.5, marca);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReachChartPainter old) {
    return old.progress != progress ||
        old.days != days ||
        old.lineColor != lineColor;
  }
}

/// Funil: cada degrau é uma barra proporcional ao topo, com a taxa de
/// conversão do degrau anterior ao lado.
class ReachFunnel extends StatelessWidget {
  const ReachFunnel({super.key, required this.steps});

  final List<ReachStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final topo = steps.isEmpty ? 0 : steps.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _FunnelBar(
            step: steps[i],
            fraction: topo == 0 ? 0 : steps[i].value / topo,
            // Cada degrau entra logo depois do anterior: a sequência conta a
            // história do funil na ordem em que ela acontece.
            delay: Duration(milliseconds: 90 * i),
            color: switch (i) {
              0 => colors.primary,
              1 => colors.officePurple,
              _ => colors.success,
            },
          ),
        ],
      ],
    );
  }
}

class _FunnelBar extends StatelessWidget {
  const _FunnelBar({
    required this.step,
    required this.fraction,
    required this.delay,
    required this.color,
  });

  final ReachStep step;
  final double fraction;
  final Duration delay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final semAnimacao = JuriiMotion.disabled(context);

    return Semantics(
      // O leitor de tela recebe a frase inteira; a barra sozinha não diz nada.
      label: step.rateFromPrevious == null
          ? '${step.value} ${step.label}'
          : '${step.value} ${step.label}, '
                '${(step.rateFromPrevious! * 100).round()} por cento',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _CountUp(value: step.value, delay: delay, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.label,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (step.rateFromPrevious != null)
                  Text(
                    '${(step.rateFromPrevious! * 100).round()}%',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction.clamp(0, 1)),
                duration: semAnimacao
                    ? Duration.zero
                    : JuriiMotion.slow + delay,
                curve: JuriiMotion.ease,
                builder: (context, valor, _) {
                  return LinearProgressIndicator(
                    value: valor,
                    minHeight: 8,
                    backgroundColor: colors.lightBlue,
                    color: color,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Número que sobe de zero até o valor. É o detalhe que faz o painel parecer
/// vivo — e como o alcance é o argumento de venda do patrocínio, vê-lo subir
/// vale mais que vê-lo simplesmente aparecer.
class _CountUp extends StatelessWidget {
  const _CountUp({
    required this.value,
    required this.delay,
    required this.color,
  });

  final int value;
  final Duration delay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final semAnimacao = JuriiMotion.disabled(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: semAnimacao ? Duration.zero : JuriiMotion.slow + delay,
      curve: JuriiMotion.ease,
      builder: (context, valor, _) {
        return Text(
          valor.round().toString(),
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            // Largura fixa de dígito: sem isso o número treme enquanto sobe,
            // porque cada algarismo tem largura diferente.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

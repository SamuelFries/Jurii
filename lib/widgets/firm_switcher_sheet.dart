import 'package:flutter/material.dart';

import '../models/firm_membership.dart';
import '../theme/app_colors.dart';

/// Seletor de ESCRITÓRIO.
///
/// É irmão de [showModeSwitcher], e de propósito: lá se troca de ÁREA
/// (cliente, advogado, escritório), aqui se troca de escritório dentro da
/// área. Mesma folha, mesma linha, mesmo roxo do escritório, porque é a mesma
/// pergunta feita um nível abaixo. Inventar outra aparência faria a pessoa
/// reaprender onde procurar, que foi exatamente o problema que a folha de
/// áreas resolveu quando havia três lugares diferentes para trocar de fluxo.
///
/// Trocar NÃO mexe em vínculo: quem é sócio numa banca e advogado em outra
/// continua sendo as duas coisas depois de escolher.
Future<void> showFirmSwitcher(
  BuildContext context, {
  required List<FirmMembership> memberships,
  required String? currentFirmId,
  required ValueChanged<String> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      // A MESMA moldura da folha de áreas: cartão flutuante, borda do tema,
      // canto de 24. Duas folhas de troca com aparências diferentes fariam a
      // pessoa achar que são coisas de naturezas diferentes.
      final colors = sheetContext.jColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: colors.card,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: colors.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  child: Text(
                    'Atuando como',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Você faz parte de mais de um escritório. Trocar aqui muda '
                    'o contexto, e não os seus vínculos.',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                for (final membership in memberships)
                  _FirmRow(
                    membership: membership,
                    isCurrent: membership.firmId == currentFirmId,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onSelect(membership.firmId);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// O seletor só faz sentido com dois ou mais: com um vínculo só, ele seria um
/// botão que abre uma lista de um item, e o nome do escritório já está no topo
/// da tela.
bool shouldShowFirmSwitcher(List<FirmMembership> memberships) =>
    memberships.length > 1;

class _FirmRow extends StatelessWidget {
  const _FirmRow({
    required this.membership,
    required this.isCurrent,
    required this.onTap,
  });

  final FirmMembership membership;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final cor = colors.officePurple;

    return ListTile(
      // O escritório aberto não é toque morto: fica marcado e não navega.
      onTap: isCurrent ? null : onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: Text(
          membership.initials,
          style: TextStyle(color: cor, fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(
        membership.firmName,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      // O CARGO fica embaixo do nome porque ele é a metade da resposta: a
      // mesma pessoa é sócia numa banca e estagiária em outra, e sem o cargo
      // a lista não diz o que muda ao escolher.
      subtitle: Text(
        membership.primaryRole.label,
        style: TextStyle(color: colors.textSecondary, fontSize: 12),
      ),
      trailing: isCurrent
          ? Icon(Icons.check_circle, color: cor, size: 20)
          : null,
    );
  }
}

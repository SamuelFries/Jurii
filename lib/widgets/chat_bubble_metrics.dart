import 'dart:math' as math;

/// Larguras máximas dos balões da conversa.
///
/// A regra antiga era só uma porcentagem da tela (78% para balão, 88% para os
/// cartões). Isso funciona no celular, onde 78% de 400dp é um balão de 312dp, e
/// desanda em tela larga: no navegador, 78% viram mais de 1500px de balão.
///
/// O texto escondia o problema porque balão de texto encolhe até o conteúdo —
/// quem denunciou foi a mídia, que ocupa a largura inteira que lhe derem e
/// virava uma faixa de 1500x240 com a foto cortada numa tira.
///
/// Por isso o teto é ABSOLUTO junto com a porcentagem: a porcentagem manda no
/// celular, o teto manda no resto.
const double kChatBubbleMaxWidth = 420;

/// Cartões (solicitação de caso, sugestão de advogado) podem ser um pouco mais
/// largos que o balão: têm duas colunas de informação e botões lado a lado.
const double kChatCardMaxWidth = 520;

/// Lado da prévia de mídia dentro do balão.
///
/// QUADRADA de propósito. A mensagem não guarda as dimensões da foto, então
/// alguma proporção fixa tem que ser escolhida — e o corte central de um
/// quadrado é o que trata melhor os dois casos: uma foto retrato 3:4 perde
/// ~25% da altura, uma paisagem 4:3 perde ~25% da largura. A caixa deitada que
/// existia antes (1,7:1) comia mais da metade de uma foto retrato, que é
/// justamente o formato de foto de documento — o caso mais comum daqui.
const double kChatMediaSide = 280;

/// Largura do balão de mensagem para uma tela de [screenWidth].
double chatBubbleWidthFor(double screenWidth) =>
    math.min(screenWidth * 0.78, kChatBubbleMaxWidth);

/// Largura dos cartões de caso e de sugestão de advogado.
double chatCardWidthFor(double screenWidth) =>
    math.min(screenWidth * 0.88, kChatCardMaxWidth);

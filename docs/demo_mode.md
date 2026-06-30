# Modo demo para pitch

Para gravar video com o app preenchido por dados mockados, rode:

```powershell
flutter run --dart-define=JURII_DEMO_MODE=true
```

Nesse modo o app ignora o Supabase, inicia com usuario aprovado, libera o modo
profissional e a area do escritorio, e usa os mocks de home, mensagens, casos,
agenda, notificacoes e equipe.

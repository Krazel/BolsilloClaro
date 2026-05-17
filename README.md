# Bolsillo Claro

App nativa simple de finanzas personales.

## Idea

Bolsillo Claro responde rapido a tres preguntas:

- Cuanto dinero queda disponible.
- Cuanto se ha gastado este mes.
- Cuales fueron los ultimos movimientos.

La primera version mantiene una pantalla principal minimalista, modo claro/oscuro automatico, categorias basicas y alta rapida de movimientos.

## IDs fijos

- iOS Bundle ID: `com.dmkr.bolsilloclaro`
- Android Package ID: `com.dmkr.bolsilloclaro`

## Estructura

- `native-ios/`: app iPhone nativa en SwiftUI.
- `android/`: app Android nativa en Java.
- `.github/workflows/build-ios-unsigned.yml`: build de IPA unsigned en GitHub Actions.
- `artifact/`: builds descargadas o copiadas localmente.

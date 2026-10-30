# Centro de datos

App para iPhone que empaqueta la web app `Centro de datos` (`App/Web/index.html`) dentro de un `WKWebView` nativo.

## Cómo funciona

- El HTML original se incluye tal cual en la app y se carga con el origen `https://localhost`, para que Firebase, `localStorage` y el portapapeles funcionen igual que en el navegador.
- `App/Sources/Bridge.swift` añade lo que Safari hace por su cuenta y un WebView no:
  - Las exportaciones a Excel y CSV abren la hoja de compartir de iOS (Guardar en Archivos, WhatsApp, Mail…).
  - Los enlaces externos y de WhatsApp (`wa.me`) se abren en su app.
  - `alert`, `confirm` y `prompt` se muestran como alertas nativas.
  - La barra de estado y el fondo siguen el tema claro u oscuro de la página.
- Para actualizar la app, sustituye `App/Web/index.html` por la nueva versión y sube el cambio.

## Compilación

El proyecto se genera con XcodeGen y se compila en GitHub Actions sobre macOS, sin necesidad de una Mac propia.

- **Cualquier rama:** genera un IPA sin firmar, que se descarga como artefacto desde la pestaña *Actions*.
- **`main`:** además firma la app con fastlane `match` (certificado guardado en la rama `certificados`) y la sube a TestFlight. Para ello necesita estos secrets del repositorio: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` y `APPLE_TEAM_ID`.

Identificador de la app: `com.lfaz.centrodedatos`.

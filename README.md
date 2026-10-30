# Centro de datos

App nativa para iPhone (Swift + SwiftUI) de Centro de datos, el sistema de cartera de créditos que hoy funciona como web app. Usa la **misma base de datos de Firebase** que la versión web, así que las dos se pueden usar a la vez.

## Fases

1. **Núcleo (esta versión):** inicio de sesión con los mismos usuarios, permisos por rol (admin/asesor), PIN de bloqueo y bloqueo por inactividad; Inicio con pagos de hoy, PR aprobadas, liquidaciones de la semana, seguimiento y pagos atrasados; Base de datos con las 6 categorías, búsqueda, filtros, ficha completa, altas y ediciones (incluida la detección de doble financiamiento, renovaciones, referencias y PR adjuntas), pagos, estatus, macropesos, seguimiento y notificaciones.
2. **Herramientas:** ver pagos, recordatorios y mensajes masivos por WhatsApp con plantillas y días de bloqueo.
3. **Administración:** catálogos, usuarios, asesores, auditoría, exportación a Excel/CSV.

## Compatibilidad con la web

- Los registros se guardan como JSON sin perder campos que la app no conozca.
- Cada guardado escribe solo los campos que cambiaron y sube la revisión `_rev` de cada cliente, igual que la web, para que las reglas de Firebase rechacen ediciones simultáneas en conflicto.
- Cada guardado deja su entrada en `ca_auditoria`.
- El mantenimiento automático (créditos finalizados, PR que pasan a prospecto, PR adjuntas expiradas) lo ejecuta la sesión del administrador, como en la web.
- A diferencia de la web, editar un cliente conserva todos sus demás datos (doble financiamiento, pagos marcados como no pagados, envíos, etc.).

`Referencia/Centro-de-datos.html` es la web app original, que sirve como referencia funcional.

## Firebase

Para que la app quede registrada como app iOS en el proyecto `basededatos-29c60`, añade `App/Resources/GoogleService-Info.plist` (Firebase console → Configuración del proyecto → Agregar app iOS con el ID `com.lfaz.centrodedatos`). Mientras no exista, la app usa la configuración del proyecto web.

## Compilación

El proyecto se genera con XcodeGen y se compila en GitHub Actions sobre macOS, sin necesidad de una Mac propia. Firebase se descarga con Swift Package Manager.

- **Cualquier rama:** ejecuta las pruebas unitarias en el simulador y genera un IPA sin firmar, que se descarga como artefacto desde la pestaña *Actions*.
- **`main`:** además firma la app con fastlane `match` (certificado guardado en la rama `certificados`) y la sube a TestFlight. Necesita estos secrets del repositorio: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` y `APPLE_TEAM_ID`.

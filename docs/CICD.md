# CI/CD — Bocadoo Mobile (Flutter)

La automatización de integración y entrega continua corre en **GitHub Actions** (runners Linux `ubuntu-latest`), evitando ejecutar `flutter analyze` o `flutter test` en la terminal del agente sobre Windows.

---

## 1. Workflows implementados

### `Flutter CI (Bocadoo)` — [`.github/workflows/flutter-ci.yml`](../.github/workflows/flutter-ci.yml)
Se dispara automáticamente en:
- `push` a `main`, `feat/**`, `fix/**`, `ci/**` (cuando cambian `mobile/**`, `docs/api/openapi.json` o el propio workflow).
- `pull_request` hacia `main`.
- Ejecución manual (`workflow_dispatch`).

**Jobs:**
1. **`repo-sanity`**: valida sintaxis JSON de `docs/api/openapi.json` y verifica que no se hayan subido archivos sensibles (`.jks`, `.keystore`, `key.properties`, `.env`).
2. **`flutter-quality`**: instala Flutter (`stable` con caché), ejecuta `flutter pub get`, verifica formato (`dart format` como advertencia), corre `flutter analyze --no-fatal-infos` y `flutter test --coverage`, subiendo `lcov.info` como artifact.
3. **`android-debug-build`**: (en PRs, `main` y ejecución manual) configura Java 17 + Gradle, restaura el wrapper de Gradle si está ignorado por `.gitignore`, compila `app-debug.apk` y lo sube como artifact descargable (`bocadoo-android-debug-apk`).

---

### `Flutter CD (Release Android)` — [`.github/workflows/flutter-cd.yml`](../.github/workflows/flutter-cd.yml)
Se dispara al:
- Publicar un tag semántico (`git tag v1.0.0 && git push origin v1.0.0`).
- Ejecutar manualmente (`Actions → Flutter CD (Release Android) → Run workflow`) eligiendo:
  - `environment`: `production` | `staging` | `mock`
  - `api_url`: override opcional de `BOCADOO_API_URL`
  - `build_aab`: generar `.aab` para Google Play
  - `publish_release`: publicar GitHub Release con los binarios y `SHA256SUMS.txt`

**Artifacts generados:**
- `bocadoo-<env>-universal.apk`
- `bocadoo-<env>-arm64-v8a.apk` y `bocadoo-<env>-armeabi-v7a.apk`
- `bocadoo-<env>.aab` (si aplica)
- `SHA256SUMS.txt`

---

## 2. Variables y Secrets opcionales en GitHub

En **Repository Settings → Secrets and variables → Actions**:

### Variables (`Variables`)
| Nombre | Descripción | Valor por defecto |
| --- | --- | --- |
| `BOCADOO_API_URL` | URL base del backend en producción | `https://bck-bocadoo.onrender.com` |
| `BOCADOO_STAGING_API_URL` | URL base para builds de `staging` | `https://bck-bocadoo.onrender.com` |
| `BOCADOO_SUPPORT_WHATSAPP` | WhatsApp de soporte (`5939XXXXXXXX`) | *(vacío)* |
| `BOCADOO_SUPPORT_URL` | URL de ayuda | *(vacío)* |

### Firma Android de Release (`Secrets`)
Mientras no se configuren estos 4 secrets, `android/app/build.gradle.kts` compila con firma `debug` de respaldo (ideal para pruebas internas, no para Play Store). Al agregarlos, la firma de producción se activa automáticamente:

| Secret | Cómo generarlo |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | En Linux/macOS: `base64 -w 0 upload-keystore.jks` · En PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks"))` |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del archivo `.jks` |
| `ANDROID_KEY_ALIAS` | Alias de la llave (ej. `upload` o `bocadoo`) |
| `ANDROID_KEY_PASSWORD` | Contraseña de la llave |

---

## 3. Dependabot y PRs
- [`.github/dependabot.yml`](../.github/dependabot.yml): revisa semanalmente actualizaciones de paquetes `pub` (`/mobile`), `gradle` (`/mobile/android`) y `github-actions`.
- [`.github/pull_request_template.md`](../.github/pull_request_template.md): plantilla de PR alineada con las reglas de `GEMINI.md`.

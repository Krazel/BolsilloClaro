# Build iOS desde GitHub

La app iOS se compila con GitHub Actions porque necesita macOS y Xcode.

Flujo:

```powershell
git add -A
git commit -m "Initial commit"
..\gh.bat repo create BolsilloClaro --public --source . --remote origin --push
.\watch-ipa.bat
```

El watcher descarga la IPA unsigned generada por el workflow y deja una sola IPA visible en `artifact/`.

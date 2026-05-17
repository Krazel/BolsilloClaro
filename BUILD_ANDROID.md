# Build Android

Desde la raiz del workspace:

```powershell
.\android-env.bat
cd BolsilloClaro\android
.\gradlew.bat assembleDebug
```

APK esperado:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

Copiar la build visible a:

```text
artifact/BolsilloClaro-Android-v1.1-local.apk
```

Antes de dejar una nueva build visible, mover APKs antiguos a `artifact/old/`.

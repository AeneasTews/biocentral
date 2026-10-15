# Building

Overview how to build biocentral for different platforms locally.

For serious_python, you need to add this environment variable to your run configuration:

`SERIOUS_PYTHON_VERSION` must match the version used when packaging the companion below --
the native runtime embedded by `flutter run`/`flutter build` otherwise defaults to a
different CPython version than the one the compiled dependencies (e.g. `h5py`) were built
for, which fails to import at runtime.

```shell
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/app
export SERIOUS_PYTHON_VERSION=3.12
flutter run -d linux

# For IDE config
SERIOUS_PYTHON_SITE_PACKAGES=/absolute/path/to/biocentral/build/site-packages
SERIOUS_PYTHON_APP=/absolute/path/to/biocentral/build/app
SERIOUS_PYTHON_VERSION=3.12
```

Create the launcher icons:

```shell
dart run flutter_launcher_icons
```

## Python Companion

Build python companion via `serious_python` package command before building the flutter app:

```shell
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/app
# Pin to 3.12: requirements.txt's scipy/h5py versions have no prebuilt wheels for newer CPython.
export SERIOUS_PYTHON_VERSION=3.12
# Windows
dart run serious_python:main package python_companion/ -p Windows -r -r -r python_companion/requirements.txt
# Linux
dart run serious_python:main package python_companion/ -p Linux -r -r -r python_companion/requirements.txt
# macOS
dart run serious_python:main package python_companion/ -p Darwin -r -r -r python_companion/requirements.txt
# Web (serious_python 5.0.0 dropped web support; left here for when that returns)
dart run serious_python:main package --asset assets/python_companion.zip python_companion/ -p Pyodide -r -r -r python_companion/requirements.txt

cp -r python_companion/ assets/
rm -rf assets/python_companion/{.idea,__pypackages__,venv,.venv}
```

## Linux

```shell
# Create release build
flutter build linux --release
```

### AppImage

```shell
# Download AppImageKit: https://github.com/AppImage/AppImageKit/releases
# Change file mode
chmod +x appimagetool-x86_64.AppImage

# Copy release to AppDir directory
cp -r build/linux/x64/release/bundle/ releases/current/biocentral.AppDir

# Create AppRun file
#!/bin/sh
cd "$(dirname "$0")"
exec ./biocentral

# Change file mode
chmod +x AppRun

# Create .desktop file https://wiki.ubuntuusers.de/.desktop-Dateien/
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Name=Biocentral
Comment=Biomedical data, from lab to paper.
Exec=biocentral %u
Icon=biocentral_logo
Categories=Science;

# Copy logo to dir
cp assets/biocentral_logo/biocentral_logo.png releases/current/biocentral.AppDir/

# Bundling to AppImage
./appimagetool-x86_64.AppImage biocentral.AppDir/ biocentral_vX.X.X.AppImage
```

## Web

```shell
flutter build web
```

## Windows

```shell
# Create release build (.exe)
flutter build windows --release
```

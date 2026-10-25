# Vocab Dictionary & Flashcards (Flutter)

Android offline/online vocabulary dictionary with speech (TTS) and repetition flashcards.

## Project Structure

- `lib/main.dart`: Complete single-file production code (SQLite DB, TTS, MyMemory API, UI).
- `pubspec.yaml`: Minimal dependencies configuration.
- `android/app/src/main/AndroidManifest.xml`: Configured `<queries>` for TTS on Android 11+.

## Supported Language Pairs
- `RU ⇄ EN`
- `RO ⇄ RU`
- `RO ⇄ EN`

## How to Run

1. Open this folder in your IDE or terminal:
   ```bash
   cd /Users/mac/.gemini/antigravity/scratch/vocab_dict
   ```
2. Get packages:
   ```bash
   flutter pub get
   ```
3. Run on connected Android device or emulator:
   ```bash
   flutter run
   ```

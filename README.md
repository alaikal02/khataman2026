# 📖 Khataman Quran

A Flutter app for tracking Quran khataman (completion) progress—individually or in groups—with Supabase backend, real-time updates, and local notifications.

## ✨ Features

- 👥 **Group khataman** — Join groups, claim juz slots, and track collective progress
- 🧑‍💻 **Solo (mandiri) mode** — Track your own juz completion
- 🔐 **Authentication** — Sign in with Google via Supabase
- 🔔 **Notifications** — In-app and local alerts for group activity and milestones
- ⚙️ **Settings** — Theme and app preferences

## 🛠️ Tech stack

- [Flutter](https://flutter.dev/) (Dart 3+) 💙
- [Supabase](https://supabase.com/) — auth, database, realtime ⚡
- [Provider](https://pub.dev/packages/provider) — state management
- [flutter_dotenv](https://pub.dev/packages/flutter_dotenv) — environment config

## 📋 Prerequisites

- Flutter SDK (stable channel)
- Android Studio / Xcode (for device builds)
- A Supabase project with Google OAuth configured

## 🚀 Local setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/alaikal02/khataman2026.git
   cd khataman2026
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Configure environment variables** 🔑

   Create a `.env` file in the project root (not committed to git):

   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key
   ```

4. **Run the app** ▶️

   ```bash
   flutter run
   ```

## 📦 Build release APK (local)

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## 🚢 Releases (CI)

Pushing to `main` triggers the [Android release workflow](.github/workflows/android-release.yml), which:

1. 📌 Reads the version from `pubspec.yaml` (e.g. `1.0.0+1`)
2. 🔨 Builds a release APK
3. 📤 Publishes it to **[GitHub Releases](https://github.com/alaikal02/khataman2026/releases)** as `khataman-quran-{version}-build{build}.apk`

### 🔢 Before each release

Bump the version in `pubspec.yaml`:

```yaml
version: 1.0.1+2   # name+build — increment for every release
```

### 🔒 Repository secrets (maintainers)

Required in **Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anon/public key |

## 📁 Project structure

```
lib/
├── main.dart
├── components/     # Reusable UI widgets
├── providers/      # Auth & settings state
├── screens/        # App screens (home, group, mandiri, etc.)
├── services/       # Notifications and backend helpers
└── theme/          # App theming
```

## 📄 License

Private project — see repository owner for usage terms.

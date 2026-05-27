import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

// Screens
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/custom_loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Memaksa durasi animasi berjalan 100% normal (mencegah lag / slow-motion debug)
    timeDilation = 1.0;

    final settings = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      title: 'Khataman Quran',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme,    // tema terang
      darkTheme: AppTheme.darkTheme, // tema gelap
      builder: (context, child) {
        // Menggunakan MediaQuery.of(context) agar data padding (Safe Area) dan dimensi layar terwarisi serta terupdate dengan benar.
        final data = MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(settings.fontSize),
        );
        return MediaQuery(
          data: data,
          child: child!,
        );
      },
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);

    if (authProvider.isLoading) {
      return const CustomLoadingScreen();
    }

    if (authProvider.user != null) {
      return const HomeScreen();
    }

    return const AuthScreen();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final AuthProvider _authProvider;
  late final AppProvider _appProvider;
  late final VoidCallback _authListener;

  @override
  void initState() {
    super.initState();
    _authProvider = context.read<AuthProvider>();
    _appProvider = context.read<AppProvider>();
    _authListener = () => _appProvider.setAuthState(_authProvider.isLoggedIn);
    _authProvider.addListener(_authListener);
    // 覆盖注册监听前已完成的会话恢复
    _authListener();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_authListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    return MaterialApp(
      title: 'SecRandom Lite',
      themeMode: appProvider.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
        fontFamilyFallback: const ['PingFang SC', 'Heiti SC', 'sans-serif'],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66CCFF),
          primary: const Color(0xFF66CCFF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
        fontFamilyFallback: const ['PingFang SC', 'Heiti SC', 'sans-serif'],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66CCFF),
          primary: const Color(0xFF66CCFF),
          brightness: Brightness.dark,
        ),
        // 深色模式下通常不需要特定的 scaffoldBackgroundColor，使用默认的深灰色即可
      ),
      home: const HomeScreen(),
    );
  }
}

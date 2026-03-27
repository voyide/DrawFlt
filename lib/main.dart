import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'drawing_state.dart';
import 'drawing_canvas.dart';
import 'panels.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUIOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  runApp(
    ChangeNotifierProvider(
      create: (_) => DrawingState(),
      child: const BrushDrawApp(),
    ),
  );
}

class BrushDrawApp extends StatelessWidget {
  const BrushDrawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brush Draw',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2B6CFF),
        useMaterial3: true,
        brightness: Brightness.light,
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF2B6CFF),
          thumbColor: Color(0xFF2B6CFF),
          overlayColor: Color(0x222B6CFF),
        ),
      ),
      home: const DrawingScreen(),
    );
  }
}

class DrawingScreen extends StatelessWidget {
  const DrawingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Full-screen canvas
          Positioned.fill(
            child: DrawingCanvasWidget(),
          ),
          // Toolbar overlay (top-left)
          Positioned(
            top: 0,
            left: 0,
            child: AppToolbar(),
          ),
        ],
      ),
    );
  }
}

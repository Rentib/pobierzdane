import 'package:flutter/material.dart';

import 'package:pobierzdane/screens/home_page.dart';

void main() {
  runApp(const PobierzDane());
}

class PobierzDane extends StatelessWidget {
  const PobierzDane({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Pobierz dane',
      themeMode: ThemeMode.system,
      home: HomePage(),
    );
  }
}

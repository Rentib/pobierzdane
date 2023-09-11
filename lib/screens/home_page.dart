import 'package:flutter/material.dart';

import 'package:pobierzdane/screens/download_page.dart';
import 'package:pobierzdane/utils/api.dart';

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  static const String routeName = '/';

  static final List<Api> apis = [
    PlanyFinansowe(),
    Sprawozdania(),
    UstawaBudzetowa(),
    Slownik(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pobierz dane'),
      ),
      body: ListView.builder(
        itemCount: apis.length,
        itemBuilder: (BuildContext context, int index) {
          return ListTile(
            title: Text(apis[index].name),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DownloadPage(api: apis[index]),
              ),
            ),
          );
        },
      )
    );
  }
}

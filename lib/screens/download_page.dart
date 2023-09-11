import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:filesystem_picker/filesystem_picker.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:pobierzdane/utils/api.dart';

class DownloadPage extends StatefulWidget {
  final Api api;

  const DownloadPage({Key? key, required this.api}) : super(key: key);

  @override
  _DownloadPageState createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  late Api api;
  late int startYear, endYear;

  @override
  void initState() {
    super.initState();
    api = widget.api;
    startYear = Api.minYear;
    endYear = Api.maxYear;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(api.name),
      ),
      body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Typ: '),
              DropdownButton<String>(
                value: api.type,
                onChanged: (String? newValue) {
                  setState(() {
                    api.type = newValue!;
                  });
                },
                items: api.types.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList()
              ),
            ],
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Zakres Lat: '),
              RangeSlider(
                values: RangeValues(startYear.toDouble(), endYear.toDouble()),
                min: Api.minYear.toDouble(),
                max: Api.maxYear.toDouble(),
                divisions: Api.maxYear - Api.minYear,
                labels: RangeLabels(startYear.toString(), endYear.toString()),
                onChanged: (RangeValues values) {
                  setState(() {
                    startYear = values.start.toInt();
                    endYear = values.end.toInt();
                  });
                },
              ),
            ],
          ),

          ElevatedButton(
            onPressed: () async {
              ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);

              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Pobieranie danych...'),
                ),
              );

              String csv;
              try {
                csv = await api.get(
                  context: context,
                  startYear: startYear,
                  endYear: endYear,
                );
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Nie udało się pobrać danych: ${e.toString().split(':')[1]}'),
                  ),
                );

                return;
              }

              Uint8List bytes = Uint8List.fromList(csv.codeUnits);
              String filename = '${api.name}-${api.type}-$startYear-$endYear.csv';

              if (kIsWeb) {
                final blob = html.Blob([bytes]);
                final url = html.Url.createObjectUrlFromBlob(blob);

                html.AnchorElement(href: url)
                  ..target = 'blank'
                  ..download = filename
                  ..click();

                html.Url.revokeObjectUrl(url);
                return;
              }
              
              try {
                String home;
                if (Platform.isWindows) {
                  final userProfile = Platform.environment['USERPROFILE'];
                  if (userProfile == null) {
                    throw Exception('Nie można pobrać ścieżki do katalogu domowego');
                  }
                  home = userProfile;
                } else if (Platform.isLinux) {
                  final homeDir = Platform.environment['HOME'];
                  if (homeDir == null) {
                    throw Exception('Nie można pobrać ścieżki do katalogu domowego');
                  }
                  home = homeDir;
                } else {
                  throw Exception('Nieobsługiwany system operacyjny');
                }

                String? path = await FilesystemPicker.openDialog(
                  title: 'Zapisz',
                  context: context,
                  rootDirectory: Directory(home),
                  fsType: FilesystemType.folder,
                  pickText: 'Wybierz',
                  folderIconColor: Colors.teal,
                );

                File file = File('$path/$filename');
                await file.writeAsBytes(bytes);
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Nie udało się zapisać pliku'),
                  ),
                );
                return;
              }

              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Pobrano dane'),
                ),
              );
            },
            child: const Text('Pobierz'),
          ),
        ],
      )),
    );
  }
}

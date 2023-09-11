import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:sn_progress_dialog/options/cancel.dart';
import 'package:sn_progress_dialog/options/completed.dart';
import 'package:sn_progress_dialog/progress_dialog.dart';

abstract class Api {
  static const int minYear = 2015;
  static final int maxYear = DateTime.now().year + 1;

  static const String _baseUrl = 'trezor-api.mf.gov.pl';
  static const String _apiVersion = 'v1';

  final String _apiPath;
  final String _name;
  get name => _name;

  final List<String> _types;
  get types => _types;
  String _type;
  String get type => _type;
  set type(String type) {
    if (!_types.contains(type)) {
      throw ArgumentError('type must be one of $_types');
    }
    _type = type;
  }

  final String _sort;
  static const int _limit = 500; // stupid trezor api doesn't allow more than 500 records per request
  static const String _format = 'csv';

  Api({
    required String apiPath,
    required String name,
    required List<String> types,
    required String sort,
  }) : _apiPath = apiPath, _name = name, _types = types, _sort = sort, _type = types.first;

  Future<String> get({
    required BuildContext context,
    required int startYear,
    required int endYear,
  }) async {
    if (startYear < minYear || endYear > maxYear) {
      throw ArgumentError('startYear must be >= $minYear and endYear must be <= $maxYear');
    }
    if (startYear > endYear) {
      throw ArgumentError('startYear must be <= endYear');
    }

    // TODO: change to List<Future<String>> to optimize sending requests
    List<String> responses = [];

    bool interrupted = false;
    var client = http.Client();
    ProgressDialog pd = ProgressDialog(context: context);

    // FIXME: progress dialog is broken
    pd.show(
      max: 1,
      msg: 'Przygotowywanie pobierania...',
      progressType: ProgressType.valuable,
      cancel: Cancel(
        cancelClicked: () {
          interrupted = true;
        }
      ),
    );

    try {
      int totalPages = 0;

      Map<int, int> pagesInYear = {};
      for (int year = startYear; year <= endYear; ++year) {
        int low = 1, high = 1000000;

        while (low < high) {
          if (interrupted) {
            throw Exception('Anulowano pobieranie danych');
          }

          int mid = low + ((high - low) >> 1); // avoid overflow
          var response = await client.get(
            Uri.https(_baseUrl, _apiPath + _type, {
              'rok': year.toString(),
              'format': _format,
              'limit': _limit.toString(),
              'page': mid.toString(),
              'sort': _sort,
            }),
          );

          if (response.statusCode == 429) {
            await Future.delayed(const Duration(seconds: 5));
            continue;
          } else if (response.statusCode == 400) {
            throw Exception('Błąd 400: Nieprawidłowe parametry zapytania');
          } else if (response.statusCode == 404) {
            throw Exception('Błąd 404: Brak komunikacji z serwerem');
          } else if (response.statusCode == 500) {
            throw Exception('Błąd 500: Wewnętrzny błąd serwera');
          }

          if (response.statusCode == 200) {
            low = mid + 1;
          } else {
            high = mid;
          }
        }

        totalPages += low - 1;
        pagesInYear[year] = low - 1;
      }

      pd.close();
      pd.show(
        max: totalPages,
        msg: 'Pobieranie danych...',
        progressType: ProgressType.valuable,
        cancel: Cancel(
          cancelClicked: () {
            interrupted = true;
          }
        ),
        completed: Completed(),
      );

      for (int year = startYear; year <= endYear; ++year) {
        if (interrupted) {
          throw Exception('Anulowano pobieranie danych');
        }

        for (int page = 1; page <= pagesInYear[year]!; ++page) {
          var response = await client.get(
            Uri.https(_baseUrl, _apiPath + _type, {
              'rok': year.toString(),
              'format': _format,
              'limit': _limit.toString(),
              'page': page.toString(),
              'sort': _sort,
            }),
          );

          if (response.statusCode == 429) {
            await Future.delayed(const Duration(seconds: 5));
            --page;
            continue;
          } else if (response.statusCode == 200) {
            responses.add(response.body);
            pd.update(value: responses.length);
          } else if (response.statusCode == 400) {
            throw Exception('Błąd 400: Nieprawidłowe parametry zapytania');
          } else if (response.statusCode == 404) {
            throw Exception('Błąd 404: Brak komunikacji z serwerem');
          } else if (response.statusCode == 500) {
            throw Exception('Błąd 500: Wewnętrzny błąd serwera');
          }
        }
      }
    } catch (e) {
      pd.close();
      client.close();
      rethrow;
    } finally {
      client.close();
    }

    if (responses.isEmpty) {
      throw Exception('Brak danych w wybranym zakresie');
    }

    String csv = responses.first;
    for (int i = 1; i < responses.length; ++i) {
      csv += responses[i].split('\n').skip(2).join('\n');
    }

    return const ListToCsvConverter(fieldDelimiter: ';').convert(const CsvToListConverter(fieldDelimiter: ',').convert(csv));
  }
}

class PlanyFinansowe extends Api {
  PlanyFinansowe() : super(
    apiPath: 'api/${Api._apiVersion}/plany-finansowe-',
    name: 'Plany Finansowe',
    types: ['dochody', 'wydatki'],
    sort: 'rok',
  );
}

class Sprawozdania extends Api {
  Sprawozdania() : super(
    apiPath: 'api/${Api._apiVersion}/sprawozdania-',
    name: 'Sprawozdania',
    types: ['RB50', 'RB28', 'RB27'],
    sort: 'rok',
  );
}

class UstawaBudzetowa extends Api {
  UstawaBudzetowa() : super(
    apiPath: 'api/${Api._apiVersion}/ustawa-budzetowa-',
    name: 'Ustawa Budżetowa',
    types: ['dochody', 'rezerwy', 'wydatki'],
    sort: 'rok',
  );
}

class Slownik extends Api {
  Slownik() : super(
    apiPath: 'api/${Api._apiVersion}/slownik/',
    name: 'Słownik',
    types: ['czesci', 'dysponenci', 'dzialy', 'grupy-ekonomiczne', 'jednostki-budzetowe', 'paragrafy', 'rozdzialy', 'zrodla-finansowania'],
    sort: 'czesc,aktywny_od,aktywny_do',
  );

  @override
  Future<String> get({
    required BuildContext context,
    required int startYear,
    required int endYear,
  }) async {
    var client = http.Client();

    List<String> responses = [];

    try {
      for (int page = 1; ; ++page) {
        var response = await client.get(
          Uri.https(Api._baseUrl, _apiPath + type, {
            'format': Api._format,
            'limit': '500', // stupid trezor API doesn't allow more than 500
            'page': page.toString(),
            'sort': 'czesc,aktywny_od,aktywny_do',
          }),
        );

        if (response.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 5));
          --page;
          continue;
        } else if (response.statusCode != 200) {
          break;
        }

        responses.add(response.body);
      }
    } finally {
      client.close();
    }

    if (responses.isEmpty) {
      throw Exception('Brak danych w wybranym zakresie');
    }

    String csv = responses.first;
    for (int i = 1; i < responses.length; ++i) {
      csv += responses[i].split('\n').skip(2).join('\n');
    }

    List<List<dynamic>> rows = const CsvToListConverter(fieldDelimiter: ',').convert(csv);

    for (int i = 2; i < rows.length; ++i) {
      var startDate = DateTime.parse(rows[i][2]);

      if (startDate.year < startYear || startDate.year > endYear) {
        rows.removeAt(i);
        --i;
      }
    }

    return const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
  }
}

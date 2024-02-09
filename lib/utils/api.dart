import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:sn_progress_dialog/sn_progress_dialog.dart';

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
  static const int _limit =
      500; // stupid trezor api doesn't allow more than 500 records per request
  static const String _format = 'csv';

  bool _interrupted = false; // flag to interrupt downloading

  Api({
    required String apiPath,
    required String name,
    required List<String> types,
    required String sort,
  })  : _apiPath = apiPath,
        _name = name,
        _types = types,
        _sort = sort,
        _type = types.first;

  String _responsesToCSV(List<String> responses) {
    String csv = responses.first;
    for (int i = 1; i < responses.length; ++i) {
      csv += responses[i].split('\n').skip(2).join('\n');
    }

    var rows = const CsvToListConverter(
      fieldDelimiter: ',',
      shouldParseNumbers: false,
    ).convert(csv);
    return const ListToCsvConverter(
      fieldDelimiter: ';',
    ).convert(rows);
  }

  Future<int> _getPagesCount(int year) async {
    var client = http.Client();
    int low = 1, high = 1000000;
    try {
      while (low < high) {
        if (_interrupted) {
          throw Exception('Przerwano pobieranie danych');
        }

        int mid = low + ((high - low) >> 1);
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
          // no more data
          high = mid;
        }
      }
    } finally {
      client.close();
    }
    return low - 1;
  }

  Future<String> get({
    required BuildContext context,
    required int startYear,
    required int endYear,
  }) async {
    if (startYear < minYear || endYear > maxYear) {
      throw ArgumentError(
          'startYear must be >= $minYear and endYear must be <= $maxYear');
    }
    if (startYear > endYear) {
      throw ArgumentError('startYear must be <= endYear');
    }
    ProgressDialog pd = ProgressDialog(context: context);
    _interrupted = false;

    int totalPages = 0;
    Map<int, int> pagesInYear = {};

    try {
      pd.show(
        max: 1,
        msg: 'Przygotowywanie danych...',
        cancel: Cancel(
          cancelClicked: () {
            _interrupted = true;
          },
        ),
      );

      for (int year = startYear; year <= endYear; ++year) {
        pagesInYear[year] = await _getPagesCount(year);
        totalPages += pagesInYear[year]!;
      }
    } finally {
      pd.close();
    }

    if (totalPages == 0) {
      throw Exception('Brak danych w wybranym zakresie');
    }

    var client = http.Client();
    List<String> responses = [];

    pd.show(
      max: totalPages,
      msg: 'Pobieranie danych...',
      cancel: Cancel(
        cancelClicked: () {
          _interrupted = true;
        },
      ),
      completed: Completed(
        completedMsg: 'Pobieranie zakończone',
      ),
      progressType: ProgressType.valuable,
    );

    try {
      int downloadedPages = 0;
      for (int year = startYear; year <= endYear; ++year) {
        for (int page = 1; page <= pagesInYear[year]!; ++page) {
          if (_interrupted) {
            throw Exception('Przerwano pobieranie danych');
          }
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
          } else if (response.statusCode == 400) {
            throw Exception('Błąd 400: Nieprawidłowe parametry zapytania');
          } else if (response.statusCode == 404) {
            throw Exception('Błąd 404: Brak komunikacji z serwerem');
          } else if (response.statusCode == 500) {
            throw Exception('Błąd 500: Wewnętrzny błąd serwera');
          } else if (response.statusCode != 200) {
            throw Exception('Nieznany błąd');
          }

          responses.add(response.body);
          downloadedPages++;
          pd.update(value: downloadedPages);
          if (!pd.isOpen()) {
            pd.show(
              max: totalPages,
              msg: 'Pobieranie danych...',
              cancel: Cancel(
                cancelClicked: () {
                  _interrupted = true;
                },
              ),
              completed: Completed(
                completedMsg: 'Pobieranie zakończone',
              ),
              progressType: ProgressType.valuable,
            );
          }
        }
      }
    } catch (e) {
      pd.close();
      rethrow;
    } finally {
      client.close();
    }

    if (responses.isEmpty) {
      throw Exception('Brak danych w wybranym zakresie');
    }

    return _responsesToCSV(responses);
  }
}

class PlanyFinansowe extends Api {
  PlanyFinansowe()
      : super(
          apiPath: 'api/${Api._apiVersion}/plany-finansowe-',
          name: 'Plany Finansowe',
          types: ['dochody', 'wydatki'],
          sort: 'rok',
        );
}

class Sprawozdania extends Api {
  Sprawozdania()
      : super(
          apiPath: 'api/${Api._apiVersion}/sprawozdania-',
          name: 'Sprawozdania',
          types: ['RB50', 'RB28', 'RB27'],
          sort: 'rok',
        );
}

class UstawaBudzetowa extends Api {
  UstawaBudzetowa()
      : super(
          apiPath: 'api/${Api._apiVersion}/ustawa-budzetowa-',
          name: 'Ustawa Budżetowa',
          types: ['dochody', 'rezerwy', 'wydatki'],
          sort: 'rok',
        );
}

class Slownik extends Api {
  Slownik()
      : super(
          apiPath: 'api/${Api._apiVersion}/slownik/',
          name: 'Słownik',
          types: [
            'czesci',
            'dysponenci',
            'dzialy',
            'grupy-ekonomiczne',
            'jednostki-budzetowe',
            'paragrafy',
            'rozdzialy',
            'zrodla-finansowania'
          ],
          sort: 'aktywny_od,aktywny_do',
        );

  final Map<String, String> _sortParam = {
    'czesci': 'czesc',
    'dysponenci': 'id_dysp',
    'dzialy': 'dzial',
    'grupy-ekonomiczne': 'nr_grupy',
    'jednostki-budzetowe': 'id_jb',
    'paragrafy': 'paragraf',
    'rozdzialy': 'rozdzial',
    'zrodla-finansowania': 'nr_zrodla',
  };

  @override
  Future<String> get({
    required BuildContext context,
    required int startYear,
    required int endYear,
  }) async {
    List<String> responses = [];
    var client = http.Client();

    try {
      for (int page = 1;; ++page) {
        String sort =
            "${_sortParam[type]},${type == 'jednostki-budzetowe' ? 'aktywna_od,aktywna_do' : _sort}";
        var response = await client.get(
          Uri.https(Api._baseUrl, _apiPath + type, {
            'format': Api._format,
            'limit': Api._limit.toString(),
            'page': page.toString(),
            'sort': sort,
          }),
        );

        if (response.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 5));
          --page;
          continue;
        } else if (response.statusCode == 204) {
          break; // no more data
        } else if (response.statusCode == 400) {
          throw Exception('Błąd 400: Nieprawidłowe parametry zapytania');
        } else if (response.statusCode == 404) {
          throw Exception('Błąd 404: Brak komunikacji z serwerem');
        } else if (response.statusCode == 500) {
          throw Exception('Błąd 500: Wewnętrzny błąd serwera');
        } else if (response.statusCode != 200) {
          break; // no more data
        }

        responses.add(response.body);
      }
    } finally {
      client.close();
    }

    if (responses.isEmpty) {
      throw Exception('Brak danych w wybranym zakresie');
    }

    return _responsesToCSV(responses);
  }
}

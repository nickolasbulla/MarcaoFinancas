import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/expense.dart';

class NeonHelper {
  static final NeonHelper instance = NeonHelper._internal();
  NeonHelper._internal();

  static bool _initialized = false;
  static bool get isReady => _initialized;

  static late String _host;
  static late String _database;
  static late String _username;
  static late String _password;
  static late String _basicAuth;
  static late String _connectionString;

  static void initialize(String connectionString) {
    final uri = Uri.parse(
      connectionString.startsWith('postgres://')
          ? connectionString.replaceFirst('postgres://', 'postgresql://')
          : connectionString,
    );
    _connectionString = connectionString;
    _host = uri.host.replaceFirst('-pooler', '');
    _database = uri.path.replaceFirst('/', '');
    final parts = uri.userInfo.split(':');
    _username = Uri.decodeComponent(parts[0]);
    _password = parts.length > 1 ? Uri.decodeComponent(parts[1]) : '';
    _basicAuth = base64Encode(Uint8List.fromList(utf8.encode('$_username:$_password')));
    _initialized = true;
  }

  Future<List<Map<String, dynamic>>> _query(String sql, List<dynamic> params) async {
    final uri = Uri.https(_host, '/sql');
    final response = await http.post(
      uri,
      headers: {
        'Neon-Connection-String': _connectionString,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'query': sql, 'params': params}),
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('Tempo esgotado ao conectar com o banco.'),
    );

    if (response.statusCode != 200) {
      throw Exception('Erro no banco (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['rows'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<int> insertExpense(Expense expense) async {
    final rows = await _query(
      'INSERT INTO expenses (description, amount, category, date) '
      r'VALUES ($1, $2, $3, $4) RETURNING id',
      [
        expense.description,
        expense.amount,
        expense.category,
        DateFormat('yyyy-MM-dd').format(expense.date),
      ],
    );
    return int.parse(rows.first['id'].toString());
  }

  Future<List<Expense>> getExpenses({int? month, int? year, String? category}) async {
    final now = DateTime.now();
    final targetYear = year ?? now.year;
    final targetMonth = month ?? now.month;

    final startDate = DateTime(targetYear, targetMonth, 1);
    final endDate = DateTime(targetYear, targetMonth + 1, 1); // exclusivo: primeiro dia do mês seguinte

    final params = <dynamic>[
      startDate.toIso8601String(),
      endDate.toIso8601String(),
    ];

    var sql = 'SELECT id, description, amount, category, date, created_at '
        r'FROM expenses WHERE date >= $1 AND date < $2 ';

    if (category != null && category.isNotEmpty) {
      sql += r'AND LOWER(category) = LOWER($3) ';
      params.add(category);
    }

    sql += 'ORDER BY date DESC';

    final rows = await _query(sql, params);

    return rows.map((row) {
      return Expense(
        id: row['id'] != null ? int.parse(row['id'].toString()) : null,
        description: row['description'].toString(),
        amount: double.parse(row['amount'].toString()),
        category: row['category'].toString(),
        date: DateTime.parse(row['date'].toString()),
        createdAt: row['created_at'] != null
            ? DateTime.parse(row['created_at'].toString()).toLocal()
            : null,
      );
    }).toList();
  }

  Future<Map<String, double>> getTotalByCategory({int? month, int? year}) async {
    final expenses = await getExpenses(month: month, year: year);
    final totals = <String, double>{};
    for (final e in expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    return Map.fromEntries(
      totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  Future<double> getTotalSpent({int? month, int? year}) async {
    final expenses = await getExpenses(month: month, year: year);
    return expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> deleteExpense(int id) async {
    await _query(r'DELETE FROM expenses WHERE id = $1', [id]);
  }
}

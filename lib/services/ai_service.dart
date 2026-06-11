import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../database/neon_helper.dart';
import '../models/expense.dart';

class AiResponse {
  final String text;
  final List<Expense>? expensesForChart;
  final Map<String, double>? categoryTotalsForChart;
  final bool expenseSaved;

  AiResponse({
    required this.text,
    this.expensesForChart,
    this.categoryTotalsForChart,
    this.expenseSaved = false,
  });
}

class AiService {
  final String apiKey;
  final List<Map<String, dynamic>> _history = [];

  static const _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'openai/gpt-oss-120b';

  AiService({required this.apiKey}) {
    _resetHistory();
  }

  static String _buildSystemPrompt() {
    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final todayISO = DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(now);
    return '''
Você é um assistente financeiro pessoal. Seu único papel é ajudar o usuário a registrar gastos e consultar suas finanças.

Data e hora atuais: $today ($todayISO). Use este momento exato quando o usuário não especificar.

REGRAS OBRIGATÓRIAS:
- Você NUNCA inventa ou estima valores financeiros. Toda informação financeira vem EXCLUSIVAMENTE das ferramentas.
- Você NUNCA responde perguntas fora do tema de finanças pessoais.
- Quando o usuário informar um gasto, chame save_expense IMEDIATAMENTE sem fazer nenhuma pergunta.
- NUNCA pergunte a categoria. SEMPRE infira pela descrição. Se não tiver certeza, use "outros".
- NUNCA pergunte confirmação. Salve e confirme brevemente o que foi salvo.
- Quando o usuário fizer perguntas sobre seus gastos, use as ferramentas de consulta antes de responder.
- Para resumo ou total por categoria: use get_total_by_category (isso gera um gráfico de pizza automaticamente).
- Para listar gastos individuais: use get_expenses.
- Para remover um gasto: chame get_expenses para encontrar o expense_id exato, depois chame delete_expense com esse ID.
- NUNCA mostre o ID ou expense_id dos gastos ao usuário. É uso interno apenas.
- Quando get_expenses retornar um campo "formatted_list", exiba EXATAMENTE esse texto na sua resposta, sem alterar, resumir ou reformatar. Adicione apenas uma frase de introdução antes da lista.
- Responda sempre em português brasileiro de forma objetiva e amigável.
- Use R\$ para valores monetários no Brasil.

EXEMPLOS DE COMO AGIR:
- "lanche 15" → save_expense(description="lanche", amount=15, category="alimentação", date=hoje)
- "ração do gato 25" → save_expense(description="ração do gato", amount=25, category="outros", date=hoje)
- "uber 12" → save_expense(description="uber", amount=12, category="transporte", date=hoje)
- "mercado 87.50" → save_expense(description="mercado", amount=87.5, category="alimentação", date=hoje)
- "netflix" → pergunte o valor pois não foi informado
- "quanto gastei?" ou "resumo" ou "como estão meus gastos?" → get_total_by_category (gera gráfico)
- "lista meus gastos" ou "o que comprei?" → get_expenses
- "remove o lanche de 15" → get_expenses para achar o ID, depois delete_expense(id=X)

CATEGORIAS E PALAVRAS-CHAVE:
- alimentação: lanche, comida, almoço, jantar, café, restaurante, mercado, padaria, pizza, hamburguer, sushi, açaí, sorvete, ifood, rappi
- transporte: uber, 99, ônibus, metrô, gasolina, combustível, estacionamento, táxi, passagem
- moradia: aluguel, condomínio, luz, água, internet, gás, conta
- saúde: farmácia, remédio, médico, consulta, academia, plano de saúde, dentista
- lazer: cinema, bar, show, festa, viagem, jogo, streaming, Netflix, Spotify
- educação: curso, livro, escola, faculdade, material
- roupas: roupa, sapato, tênis, camisa, calça, acessório
- assinaturas: Netflix, Spotify, Amazon, aplicativo, assinatura
- imprevistos: conserto, reparo, multa, emergência, imprevisto, quebrou, estragou, vazamento, acidente, urgência
- outros: qualquer coisa que não se encaixe acima, incluindo pets
''';
  }

  static const _tools = [
    {
      'type': 'function',
      'function': {
        'name': 'save_expense',
        'description': 'Salva um gasto no banco de dados local.',
        'parameters': {
          'type': 'object',
          'properties': {
            'description': {'type': 'string', 'description': 'Descrição do gasto'},
            'amount': {'type': 'number', 'description': 'Valor em reais'},
            'category': {
              'type': 'string',
              'description': 'Categoria: alimentação, transporte, moradia, saúde, lazer, educação, roupas, assinaturas, imprevistos, ou outros',
            },
            'date': {
              'type': 'string',
              'description': 'Data e hora no formato YYYY-MM-DDTHH:MM:SS. Use o momento exato atual se não informado.',
            },
          },
          'required': ['description', 'amount', 'category', 'date'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_expenses',
        'description': 'Busca todos os gastos de um mês/ano específico, opcionalmente filtrando por categoria.',
        'parameters': {
          'type': 'object',
          'properties': {
            'month': {'type': 'integer', 'description': 'Mês (1-12). Padrão: mês atual.'},
            'year': {'type': 'integer', 'description': 'Ano (ex: 2025). Padrão: ano atual.'},
            'category': {'type': 'string', 'description': 'Filtrar por categoria específica (opcional).'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_total_by_category',
        'description': 'Retorna o total gasto por categoria em um mês.',
        'parameters': {
          'type': 'object',
          'properties': {
            'month': {'type': 'integer', 'description': 'Mês (1-12). Padrão: mês atual.'},
            'year': {'type': 'integer', 'description': 'Ano. Padrão: ano atual.'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_total_spent',
        'description': 'Retorna o total gasto em um mês.',
        'parameters': {
          'type': 'object',
          'properties': {
            'month': {'type': 'integer', 'description': 'Mês (1-12). Padrão: mês atual.'},
            'year': {'type': 'integer', 'description': 'Ano. Padrão: ano atual.'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_expense',
        'description': 'Remove um gasto pelo ID. Use get_expenses primeiro para encontrar o ID correto.',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {'type': 'integer', 'description': 'ID do gasto a ser removido.'},
          },
          'required': ['id'],
        },
      },
    },
  ];

  void _resetHistory() {
    _history.clear();
    _history.add({'role': 'system', 'content': _buildSystemPrompt()});
  }

  static bool _isRetryable(String msg) {
    return msg.contains('429') ||
        msg.contains('quota') ||
        msg.contains('rate_limit') ||
        msg.contains('503') ||
        msg.contains('overloaded');
  }

  Future<Map<String, dynamic>> _callApi() async {
    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': _model,
            'messages': _history,
            'tools': _tools,
            'tool_choice': 'auto',
            'parallel_tool_calls': false,
          }),
        )
        .timeout(const Duration(seconds: 40));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Groq error ${response.statusCode}: ${response.body}');
  }

  Future<Map<String, dynamic>> _callApiWithRetry() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await _callApi();
      } catch (e) {
        final msg = e.toString();
        if (_isRetryable(msg)) {
          if (attempt == 2) rethrow;
          await Future.delayed(Duration(seconds: 8 * (attempt + 1)));
        } else {
          rethrow;
        }
      }
    }
    throw Exception('Falha após todas as tentativas.');
  }

  Future<AiResponse> sendMessage(String userMessage) async {
    // Atualiza o timestamp do system prompt a cada mensagem
    _history[0] = {'role': 'system', 'content': _buildSystemPrompt()};
    _history.add({'role': 'user', 'content': userMessage});

    List<Expense>? chartExpenses;
    Map<String, double>? chartCategories;
    bool expenseSaved = false;
    String? expenseFormattedList;
    bool deleteCalled = false;

    while (true) {
      final data = await _callApiWithRetry();
      final message = (data['choices'] as List).first['message'] as Map<String, dynamic>;
      final toolCalls = message['tool_calls'] as List?;

      if (toolCalls == null || toolCalls.isEmpty) {
        _history.add(message);
        final String text;
        if (expenseFormattedList != null && expenseFormattedList.isNotEmpty && !deleteCalled) {
          final count = chartExpenses?.length ?? 0;
          text = 'Encontrei **$count gasto${count != 1 ? 's' : ''}**:\n\n$expenseFormattedList';
        } else {
          text = message['content'] as String? ?? 'Não consegui processar sua mensagem.';
        }
        return AiResponse(
          text: text,
          expensesForChart: chartExpenses,
          categoryTotalsForChart: chartCategories,
          expenseSaved: expenseSaved,
        );
      }

      _history.add(message);

      for (final toolCall in toolCalls) {
        final id = toolCall['id'] as String;
        final name = toolCall['function']['name'] as String;
        final args = jsonDecode(toolCall['function']['arguments'] as String) as Map<String, dynamic>;
        final result = await _handleFunctionCall(name, args);

        if (name == 'save_expense') expenseSaved = true;
        if (name == 'get_expenses') {
          chartExpenses = result['expenses'] as List<Expense>?;
          expenseFormattedList = result['formatted_list'] as String?;
        }
        if (name == 'get_total_by_category') {
          chartCategories = result['totals'] as Map<String, double>?;
        }
        if (name == 'delete_expense') deleteCalled = true;

        _history.add({
          'role': 'tool',
          'tool_call_id': id,
          'content': jsonEncode(result['json']),
        });
      }
    }
  }

  Future<Map<String, dynamic>> _handleFunctionCall(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'save_expense':
        final parsedDate = DateTime.parse(args['date'] as String);
        final expense = Expense(
          description: args['description'] as String,
          amount: (args['amount'] as num).toDouble(),
          category: args['category'] as String,
          date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
        );
        final id = await NeonHelper.instance.insertExpense(expense);
        return {
          'json': {'success': true, 'id': id, 'message': 'Gasto salvo com sucesso.'},
        };

      case 'get_expenses':
        final expenses = await NeonHelper.instance.getExpenses(
          month: args['month'] as int?,
          year: args['year'] as int?,
          category: args['category'] as String?,
        );
        final expenseList = expenses
            .map((e) => {
                  'expense_id': e.id,
                  'description': e.description,
                  'amount': e.amount,
                  'category': e.category,
                  'date': DateFormat('dd/MM/yyyy').format(e.date),
                  'horario': DateFormat('HH:mm').format(e.createdAt),
                })
            .toList();

        final sb = StringBuffer();
        for (final e in expenses) {
          final amount = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(e.amount);
          final date = DateFormat('dd/MM/yyyy').format(e.date);
          final time = DateFormat('HH:mm').format(e.createdAt);
          sb.write('- **$amount** em ${e.description} (${e.category})  \n');
          sb.write('  _$date às ${time}_\n');
        }

        return {
          'expenses': expenses,
          'formatted_list': sb.toString(),
          'json': {'expenses': expenseList, 'count': expenses.length},
        };

      case 'get_total_by_category':
        final totals = await NeonHelper.instance.getTotalByCategory(
          month: args['month'] as int?,
          year: args['year'] as int?,
        );
        return {
          'totals': totals,
          'json': {'totals': totals.map((k, v) => MapEntry(k, v))},
        };

      case 'get_total_spent':
        final total = await NeonHelper.instance.getTotalSpent(
          month: args['month'] as int?,
          year: args['year'] as int?,
        );
        return {
          'json': {'total': total},
        };

      case 'delete_expense':
        final id = args['id'];
        await NeonHelper.instance.deleteExpense(int.parse(id.toString()));
        return {
          'json': {'success': true, 'message': 'Gasto removido com sucesso.'},
        };

      default:
        return {'json': {'error': 'Função desconhecida: $name'}};
    }
  }

  void clearHistory() => _resetHistory();
}

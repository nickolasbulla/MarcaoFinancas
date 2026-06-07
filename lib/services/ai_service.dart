import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
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
  late final GenerativeModel _model;
  late ChatSession _chat;

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
- outros: qualquer coisa que não se encaixe acima, incluindo pets
''';
  }

  static final _tools = [
    Tool(functionDeclarations: [
      FunctionDeclaration(
        'save_expense',
        'Salva um gasto no banco de dados local.',
        Schema(SchemaType.object, properties: {
          'description': Schema(SchemaType.string, description: 'Descrição do gasto'),
          'amount': Schema(SchemaType.number, description: 'Valor em reais'),
          'category': Schema(SchemaType.string,
              description:
                  'Categoria: alimentação, transporte, moradia, saúde, lazer, educação, roupas, assinaturas, ou outros'),
          'date': Schema(SchemaType.string,
              description: 'Data e hora no formato YYYY-MM-DDTHH:MM:SS. Use o momento exato atual se não informado.'),
        }, requiredProperties: [
          'description',
          'amount',
          'category',
          'date'
        ]),
      ),
      FunctionDeclaration(
        'get_expenses',
        'Busca todos os gastos de um mês/ano específico, opcionalmente filtrando por categoria.',
        Schema(SchemaType.object, properties: {
          'month': Schema(SchemaType.integer,
              description: 'Mês (1-12). Padrão: mês atual.'),
          'year': Schema(SchemaType.integer,
              description: 'Ano (ex: 2025). Padrão: ano atual.'),
          'category': Schema(SchemaType.string,
              description: 'Filtrar por categoria específica (opcional).'),
        }),
      ),
      FunctionDeclaration(
        'get_total_by_category',
        'Retorna o total gasto por categoria em um mês.',
        Schema(SchemaType.object, properties: {
          'month': Schema(SchemaType.integer, description: 'Mês (1-12). Padrão: mês atual.'),
          'year': Schema(SchemaType.integer, description: 'Ano. Padrão: ano atual.'),
        }),
      ),
      FunctionDeclaration(
        'get_total_spent',
        'Retorna o total gasto em um mês.',
        Schema(SchemaType.object, properties: {
          'month': Schema(SchemaType.integer, description: 'Mês (1-12). Padrão: mês atual.'),
          'year': Schema(SchemaType.integer, description: 'Ano. Padrão: ano atual.'),
        }),
      ),
      FunctionDeclaration(
        'delete_expense',
        'Remove um gasto pelo ID. Use get_expenses primeiro para encontrar o ID correto.',
        Schema(SchemaType.object, properties: {
          'id': Schema(SchemaType.integer, description: 'ID do gasto a ser removido.'),
        }, requiredProperties: ['id']),
      ),
    ]),
  ];

  AiService({required this.apiKey}) {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      tools: _tools,
      systemInstruction: Content.system(_buildSystemPrompt()),
    );
    _chat = _model.startChat();
  }

  static int _parseRetrySeconds(String error) {
    final match = RegExp(r'retry in (\d+)').firstMatch(error);
    return (match != null ? int.parse(match.group(1)!) : 60) + 2;
  }

  static bool _isRetryable(String msg) {
    return msg.contains('429') ||
        msg.contains('quota') ||
        msg.contains('RESOURCE_EXHAUSTED') ||
        msg.contains('high demand') ||
        msg.contains('503') ||
        msg.contains('UNAVAILABLE') ||
        msg.contains('overloaded');
  }

  Future<GenerateContentResponse> _sendWithRetry(Content content) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await _chat
            .sendMessage(content)
            .timeout(const Duration(seconds: 40));
      } catch (e) {
        final msg = e.toString();
        if (_isRetryable(msg)) {
          if (attempt == 2) rethrow;
          final isRateLimit = msg.contains('429') || msg.contains('quota') || msg.contains('RESOURCE_EXHAUSTED');
          final wait = isRateLimit ? _parseRetrySeconds(msg) : (8 * (attempt + 1));
          await Future.delayed(Duration(seconds: wait));
        } else {
          rethrow;
        }
      }
    }
    throw Exception('Falha após todas as tentativas.');
  }

  Future<AiResponse> sendMessage(String userMessage) async {
    List<Expense>? chartExpenses;
    Map<String, double>? chartCategories;
    bool expenseSaved = false;
    String? expenseFormattedList;
    bool deleteCalled = false;

    var response = await _sendWithRetry(Content.text(userMessage));

    // Loop para processar function calls
    while (response.functionCalls.isNotEmpty) {
      final functionResults = <FunctionResponse>[];

      for (final call in response.functionCalls) {
        final result = await _handleFunctionCall(call);

        if (call.name == 'save_expense') expenseSaved = true;
        if (call.name == 'get_expenses') {
          chartExpenses = result['expenses'] as List<Expense>?;
          expenseFormattedList = result['formatted_list'] as String?;
        }
        if (call.name == 'get_total_by_category') {
          chartCategories = result['totals'] as Map<String, double>?;
        }
        if (call.name == 'delete_expense') {
          deleteCalled = true;
        }

        functionResults.add(FunctionResponse(call.name, result['json']));
      }

      response = await _sendWithRetry(Content.functionResponses(functionResults));
    }

    // Usa a lista formatada pelo código ao invés do texto da IA (que reformata incorretamente)
    final String text;
    if (expenseFormattedList != null && expenseFormattedList.isNotEmpty && !deleteCalled) {
      final count = chartExpenses?.length ?? 0;
      text = 'Encontrei **$count gasto${count != 1 ? 's' : ''}**:\n\n$expenseFormattedList';
    } else {
      text = response.text ?? 'Não consegui processar sua mensagem.';
    }

    return AiResponse(
      text: text,
      expensesForChart: chartExpenses,
      categoryTotalsForChart: chartCategories,
      expenseSaved: expenseSaved,
    );
  }

  Future<Map<String, dynamic>> _handleFunctionCall(FunctionCall call) async {
    final args = call.args;

    switch (call.name) {
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
                  'horario': e.createdAt != null
                      ? DateFormat('HH:mm').format(e.createdAt!)
                      : 'não registrado',
                })
            .toList();

        final sb = StringBuffer();
        for (final e in expenses) {
          final amount = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
              .format(e.amount);
          final date = DateFormat('dd/MM/yyyy').format(e.date);
          final time = e.createdAt != null
              ? DateFormat('HH:mm').format(e.createdAt!)
              : '';
          sb.write('- **$amount** em ${e.description} (${e.category})  \n');
          sb.write('  _${date} às ${time}_\n');
        }

        return {
          'expenses': expenses,
          'formatted_list': sb.toString(),
          'json': {
            'expenses': expenseList,
            'count': expenses.length,
          },
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
        return {'json': {'error': 'Função desconhecida: ${call.name}'}};
    }
  }

  void clearHistory() => _chat = _model.startChat();
}

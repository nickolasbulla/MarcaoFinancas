import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/neon_helper.dart';
import '../services/ai_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/expense_chart.dart';

class _ChatMessage {
  final String text;
  final bool isUser;
  final Map<String, double>? chartData;

  _ChatMessage({required this.text, required this.isUser, this.chartData});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  AiService? _ai;
  bool _loading = false;
  bool _apiKeySet = false;
  String? _maskedKey;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    if (!NeonHelper.isReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNeonDialog());
    } else {
      await _loadApiKey();
    }
  }

  void _showNeonDialog() {
    final connController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar banco de dados'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Os dados financeiros serão salvos na nuvem via Neon (gratuito).'),
              const SizedBox(height: 8),
              const Text(
                '1. Crie um projeto em console.neon.tech\n'
                '2. Clique em "Connect" no seu projeto\n'
                '3. Copie a connection string completa',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: connController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Connection String',
                  hintText: 'postgresql://user:senha@host/db',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              final conn = connController.text.trim();
              if (conn.isEmpty) return;
              Navigator.pop(ctx);
              await _saveNeonCredentials(conn);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNeonCredentials(String connectionString) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('neon_connection_string', connectionString);
    NeonHelper.initialize(connectionString);
    await _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    const compiledKey = String.fromEnvironment('GEMINI_KEY', defaultValue: '');
    final savedKey = prefs.getString('gemini_api_key') ?? '';
    final key = savedKey.isNotEmpty ? savedKey : compiledKey;
    if (key.isNotEmpty && savedKey.isEmpty) await prefs.setString('gemini_api_key', key);
    if (key.isNotEmpty) {
      setState(() {
        _ai = AiService(apiKey: key);
        _apiKeySet = true;
        _maskedKey = _maskKey(key);
      });
      if (_messages.isEmpty) {
        _addMessage('Olá! Pode me contar seus gastos ou me perguntar sobre suas finanças.', false);
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showApiKeyDialog());
    }
  }

  String _maskKey(String key) {
    if (key.length <= 6) return '••••••';
    return '••••••${key.substring(key.length - 4)}';
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    setState(() {
      _ai = AiService(apiKey: key);
      _apiKeySet = true;
      _maskedKey = _maskKey(key);
    });
    if (_messages.isEmpty) {
      _addMessage('Olá! Pode me contar seus gastos ou me perguntar sobre suas finanças.', false);
    }
  }

  void _showApiKeyDialog() {
    final keyController = TextEditingController();
    final hasKey = _maskedKey != null;
    showDialog(
      context: context,
      barrierDismissible: hasKey,
      builder: (ctx) => AlertDialog(
        title: const Text('API Key do Gemini'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasKey) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chave configurada',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            _maskedKey!,
                            style: const TextStyle(fontSize: 12, color: Colors.green, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Para trocar, insira uma nova chave abaixo:'),
            ] else ...[
              const Text(
                'Para usar o assistente financeiro, insira sua API key gratuita do Google Gemini.',
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Obtenha gratuitamente em: aistudio.google.com',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: hasKey ? 'Nova API key (opcional)' : 'Cole sua API key aqui',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (hasKey)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
          FilledButton(
            onPressed: () {
              if (keyController.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                _saveApiKey(keyController.text.trim());
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _addMessage(String text, bool isUser, {Map<String, double>? chartData}) {
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: isUser, chartData: chartData));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading || _ai == null) return;

    _controller.clear();
    _addMessage(text, true);
    setState(() => _loading = true);

    try {
      final response = await _ai!.sendMessage(text);
      _addMessage(
        response.text,
        false,
        chartData: response.categoryTotalsForChart,
      );
    } catch (e) {
      final msg = e.toString();
      final isOverloaded = msg.contains('high demand') || msg.contains('503') || msg.contains('UNAVAILABLE') || msg.contains('TimeoutException');
      final isQuota = msg.contains('429') || msg.contains('quota') || msg.contains('RESOURCE_EXHAUSTED');
      if (isOverloaded) {
        _addMessage('O servidor do Gemini está sobrecarregado agora. Aguarde um momento e tente de novo.', false);
      } else if (isQuota) {
        _addMessage('Limite de requisições atingido. Aguarde alguns minutos e tente de novo.', false);
      } else {
        _addMessage('Erro: $msg', false);
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marcão Finanças'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _apiKeySet ? Icons.key : Icons.key_outlined,
              color: _apiKeySet ? Colors.green : null,
            ),
            tooltip: _apiKeySet ? 'Chave configurada ($_maskedKey) — toque para alterar' : 'Configurar API key',
            onPressed: _showApiKeyDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !_apiKeySet
                ? const Center(child: Text('Configure sua API key para começar.'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = _messages[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          MessageBubble(text: msg.text, isUser: msg.isUser),
                          if (msg.chartData != null && msg.chartData!.isNotEmpty)
                            CategoryPieChart(data: msg.chartData!),
                        ],
                      );
                    },
                  ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Pensando...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ex: gastei 45 no almoço...',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _loading ? null : _sendMessage,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
            ),
            child: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

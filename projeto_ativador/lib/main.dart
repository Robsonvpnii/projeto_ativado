import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

// Caminho fixo do arquivo de configuracao solicitado.
const String kConfigPath = '/storage/emulated/0/Android/.config';

// Endpoint de ativacao.
const String kEndpoint =
    'https://fluffernutter-joy-factory.lovable.app/endpoint';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AtivadorApp());
}

class AtivadorApp extends StatelessWidget {
  const AtivadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ativador TV Box',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5A0),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
        // Realce visivel de foco para navegacao por D-Pad/controle remoto.
        focusColor: const Color(0xFF00E5A0),
      ),
      home: const SplashScreen(),
    );
  }
}

/// Tela inicial que verifica se o arquivo de config existe.
/// Se existir -> vai direto para o Painel.
/// Se nao existir -> vai para a tela de licenca.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Verificando...';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Solicita as permissoes de armazenamento antes de qualquer leitura.
    await _requestStoragePermissions();

    final bool existe = await File(kConfigPath).exists();

    if (!mounted) return;

    if (existe) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PainelScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LicencaScreen()),
      );
    }
  }

  Future<void> _requestStoragePermissions() async {
    setState(() => _status = 'Solicitando permissoes...');
    try {
      // Android <= 12
      await Permission.storage.request();
      // Android 11+ (acesso total ao armazenamento)
      if (await Permission.manageExternalStorage.isGranted == false) {
        await Permission.manageExternalStorage.request();
      }
    } catch (_) {
      // Em algumas TV Boxes o dialogo pode nao existir; seguimos assim mesmo.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.live_tv, size: 96, color: Color(0xFF00E5A0)),
            const SizedBox(height: 24),
            const Text(
              'ATIVADOR TV BOX',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Color(0xFF00E5A0)),
            const SizedBox(height: 16),
            Text(_status,
                style: const TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

/// Tela de entrada de chave de licenca + botao "Ativar".
class LicencaScreen extends StatefulWidget {
  const LicencaScreen({super.key});

  @override
  State<LicencaScreen> createState() => _LicencaScreenState();
}

class _LicencaScreenState extends State<LicencaScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _campoFocus = FocusNode();
  final FocusNode _botaoFocus = FocusNode();

  bool _carregando = false;
  String? _mensagem;

  @override
  void initState() {
    super.initState();
    // Foco inicial no campo para uso imediato com o controle remoto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _campoFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _campoFocus.dispose();
    _botaoFocus.dispose();
    super.dispose();
  }

  Future<void> _ativar() async {
    final chave = _controller.text.trim();
    if (chave.isEmpty) {
      setState(() => _mensagem = 'Digite uma chave de licenca valida.');
      return;
    }

    setState(() {
      _carregando = true;
      _mensagem = null;
    });

    try {
      final resposta = await http
          .post(
            Uri.parse(kEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'license_key': chave,
              'device': 'tvbox',
            }),
          )
          .timeout(const Duration(seconds: 30));

      final bool sucesso =
          resposta.statusCode >= 200 && resposta.statusCode < 300;

      if (sucesso) {
        await _gravarConfig(chave, resposta.body);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PainelScreen()),
        );
      } else {
        setState(() {
          _mensagem =
              'Falha na ativacao (HTTP ${resposta.statusCode}). Verifique a chave.';
        });
      }
    } catch (e) {
      setState(() => _mensagem = 'Erro de conexao: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Grava o arquivo local em /storage/emulated/0/Android/.config
  Future<void> _gravarConfig(String chave, String respostaBody) async {
    final file = File(kConfigPath);
    await file.parent.create(recursive: true);
    final conteudo = jsonEncode({
      'license_key': chave,
      'activated_at': DateTime.now().toIso8601String(),
      'server_response': respostaBody,
    });
    await file.writeAsString(conteudo, flush: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.vpn_key, size: 72, color: Color(0xFF00E5A0)),
                const SizedBox(height: 16),
                const Text(
                  'ATIVACAO DE LICENCA',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Insira sua chave de licenca para ativar o dispositivo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 15),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _controller,
                  focusNode: _campoFocus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, letterSpacing: 2),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _botaoFocus.requestFocus(),
                  decoration: InputDecoration(
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    filled: true,
                    fillColor: const Color(0xFF141B22),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF243038), width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF00E5A0), width: 3),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    focusNode: _botaoFocus,
                    autofocus: false,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5A0),
                      foregroundColor: Colors.black,
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _carregando ? null : _ativar,
                    icon: _carregando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.check_circle, size: 26),
                    label: Text(_carregando ? 'ATIVANDO...' : 'ATIVAR'),
                  ),
                ),
                if (_mensagem != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _mensagem!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela do painel exibida quando o dispositivo esta ativado.
/// Contem o botao "APAGAR CONFIG" que remove o arquivo e volta para a licenca.
class PainelScreen extends StatefulWidget {
  const PainelScreen({super.key});

  @override
  State<PainelScreen> createState() => _PainelScreenState();
}

class _PainelScreenState extends State<PainelScreen> {
  String _infoLicenca = 'Carregando informacoes...';

  @override
  void initState() {
    super.initState();
    _lerConfig();
  }

  /// Le o arquivo local /storage/emulated/0/Android/.config
  Future<void> _lerConfig() async {
    try {
      final file = File(kConfigPath);
      if (await file.exists()) {
        final conteudo = await file.readAsString();
        final Map<String, dynamic> dados = jsonDecode(conteudo);
        setState(() {
          _infoLicenca =
              'Chave: ${dados['license_key'] ?? '---'}\nAtivado em: ${dados['activated_at'] ?? '---'}';
        });
      } else {
        setState(() => _infoLicenca = 'Arquivo de configuracao nao encontrado.');
      }
    } catch (e) {
      setState(() => _infoLicenca = 'Erro ao ler configuracao: $e');
    }
  }

  Future<void> _apagarConfig() async {
    try {
      final file = File(kConfigPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignora erros de exclusao e segue para a tela inicial.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LicencaScreen()),
    );
  }

  Future<void> _confirmarApagar() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B22),
        title: const Text('Apagar configuracao?'),
        content: const Text(
          'Isso removera a licenca deste dispositivo e voltara para a tela de ativacao.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            autofocus: true,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('APAGAR'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _apagarConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified, size: 84, color: Color(0xFF00E5A0)),
                const SizedBox(height: 16),
                const Text(
                  'DISPOSITIVO ATIVADO',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141B22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF243038)),
                  ),
                  child: Text(
                    _infoLicenca,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    autofocus: true,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B6B),
                      foregroundColor: Colors.black,
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _confirmarApagar,
                    icon: const Icon(Icons.delete_forever, size: 26),
                    label: const Text('APAGAR CONFIG'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

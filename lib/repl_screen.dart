import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'parser.dart';

class ReplScreen extends StatefulWidget {
  final Future<String> Function()? onParse;
  const ReplScreen({super.key, this.onParse});
  @override
  State<ReplScreen> createState() => _ReplScreenState();
}

class _ReplScreenState extends State<ReplScreen> {
  final _controller = TextEditingController();
  final List<String> _log = [];
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) => _prefs = p);
    _log.add('REPL готов. Введи help.');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    final cmd = _controller.text.trim();
    if (cmd.isEmpty) return;
    setState(() => _log.add('> $cmd'));
    _controller.clear();
    final parts = cmd.split(' ');
    final action = parts[0].toLowerCase();

    if (action == 'help') {
      setState(() => _log.addAll([
        'help',
        'set KEY VALUE',
        'get KEY',
        'reset',
        'parse',
      ]));
      return;
    }

    if (action == 'parse') {
      if (widget.onParse == null) {
        setState(() => _log.add('ERR: parse недоступен'));
        return;
      }
      setState(() => _log.add('Парсинг запущен...'));
      try {
        final result = await widget.onParse!();
        setState(() => _log.add(result));
      } catch (e) {
        setState(() => _log.add('ERR: $e'));
      }
      return;
    }

    if (action == 'set' && parts.length == 3) {
      final key = parts[1];
      final val = int.tryParse(parts[2]) ?? 0;
      await _prefs?.setInt(key, val);
      await ArtifactParser.loadPrefs();
      setState(() => _log.add('OK: $key = $val'));
      return;
    }

    if (action == 'get' && parts.length == 2) {
      final key = parts[1];
      final val = _prefs?.getInt(key);
      setState(() => _log.add('$key = $val'));
      return;
    }

    if (action == 'reset') {
      _prefs?.clear();
      await ArtifactParser.loadPrefs();
      setState(() => _log.add('OK: все настройки сброшены'));
      return;
    }

    setState(() => _log.add('ERR: неизвестная команда'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('REPL')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(_log[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: 'команда...', border: OutlineInputBorder()),
                    onSubmitted: (_) => _execute(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _execute, child: const Text('Run')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

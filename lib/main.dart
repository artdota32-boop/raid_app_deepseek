import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:snapframes/snapframes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:image/image.dart' as img;
import 'package:paddle_ocr_native/paddle_ocr_native.dart' as pn;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'parser.dart';
import 'game_validator.dart';
import 'about_screen.dart';
import 'onnx_ocr.dart';
import 'crop_calibrator.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'repl_screen.dart';
import 'polygon/polygon_ocr_diagnostic_screen.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raid Scanner',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SharedPreferences? _prefsCache;
  String _version = "";

  @override
  void initState() {
    super.initState();
    ArtifactParser.loadPrefs();
    _loadVersion();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _prefsCache = p);
    });
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = 'v${info.version}+${info.buildNumber}';
      });
    }
  }

  File? _videoFile;
  Uint8List? _croppedBytes;
  Uint8List? _iconBytes;
  Uint8List? _lastFrame;
  String _status = 'Выбери видео';
  String _ocrText = '';
  String _parsedText = '';
  String _debugLog = '';
  final List<String> _debugBuffer = [];


  


  Future<void> _testOnnx() async {
    if (_croppedBytes == null) {
      setState(() => _status = '❌ Сначала выбери видео, чтобы получить кроп!');
      return;
    }

    setState(() => _status = 'Чтение текста через ONNX (9 полос)...');

    try {
      final img.Image? card = img.decodeImage(_croppedBytes!);
      if (card == null) {
        setState(() => _status = '❌ Не удалось декодировать карточку');
        return;
      }

      // Диагностика: сохраняем кроп для сравнения с Trainer.
      try {
        final exportDir = Directory('/storage/emulated/0/Download/raid_dataset');
        await exportDir.create(recursive: true);
        final saveFile = File('${exportDir.path}/android_crop.jpg');
        await saveFile.writeAsBytes(img.encodeJpg(card, quality: 95));
        _dprint('[ONNX] Android crop saved: ${saveFile.path}');
      } catch (e) {
        _dprint('[ONNX] Не удалось сохранить android_crop.jpg: $e');
      }
      final int h = card.height;
      final int w = card.width;
      final List<String> results = [];

      for (int i = 0; i < 10; i++) {
        int y1 = i * h ~/ 10;
        int y2 = (i + 1) * h ~/ 10;
        if (i == 7) {
          y2 = 9 * h ~/ 10;
        }
        if (i == 8) {
          continue;
        }
        if (y2 <= y1) continue;

        final stripe = img.copyCrop(
          card,
          x: 0,
          y: y1,
          width: w,
          height: y2 - y1,
        );
        final stripeBytes = Uint8List.fromList(img.encodeJpg(stripe));
        final result = await OnnxOcr.recognize(stripeBytes);
        _dprint('[ONNX DIAG] ${OnnxOcr.lastDiagnostics}');
        final clean = result.replaceFirst('Текст: ', '').trim();

        _dprint('[ONNX STRIPE ${i + 1}/10] $clean');
        final isShortNumber = RegExp(r'^[+-]?\d+(?:[.,]\d+)?%?$')
            .hasMatch(clean);

        if (clean.length >= 4 || isShortNumber) {
          results.add(clean);
        }
      }

      setState(() {
        _status = 'Результат: ${results.join(" ")}';
        _debugLog = _debugBuffer.join('\n');
      });
    } catch (e) {
      setState(() => _status = '❌ Ошибка OCR: $e');
    }
  }

  void _dprint(String line) {
    debugPrint(line);
    _debugBuffer.add(line);
    if (_debugBuffer.length > 3000) _debugBuffer.removeAt(0);
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _videoFile = File(picked.path);
        _status = 'Видео выбрано, вырезаю кадр...';
        _croppedBytes = null;
        _ocrText = '';
        _parsedText = '';
        _debugLog = '';
        _debugBuffer.clear();
      });
      await _extractFrame();
    }
  }

  Future<void> _extractFrame() async {
    if (_videoFile == null) return;
    try {
      final req = SnapRequest(
        source: _videoFile!.path,
        timestampMs: 2000,
        format: SnapImageFormat.jpg,
        quality: 90,
      );
      final bytes = await getFrameBytes(req);
      if (bytes == null) {
        setState(() => _status = 'Не удалось вырезать кадр');
        return;
      }
      _lastFrame = bytes;
      final frame = img.decodeImage(bytes);
      if (frame != null) {
        _dprint("[FRAME] ${frame.width}x${frame.height}");
      }
      final cropped = await _cropBottomLeft(bytes);
      final rightPart = _cropRightPart(bytes);
      final iconPart = _cropIcon(bytes);
      setState(() {
        _croppedBytes = cropped;
        _iconBytes = iconPart;
        _status = 'Кадр обрезан! Запускаю OCR...';
      });
      await _runOcr(cropped, rightPart, iconPart);
    } catch (e) {
      setState(() => _status = 'Ошибка: $e');
    }
  }

  Future<String> parseCurrent() async {
    if (_lastFrame == null) return 'ERR: нет кадра';
    final cropped = await _cropBottomLeft(_lastFrame!);
    if (cropped == null) return 'ERR: кроп не удался';
    final rightPart = _cropRightPart(_lastFrame!);
    final iconPart = _cropIcon(_lastFrame!);
    final ocr = pn.PaddleOcr();
    await ocr.init(
      config: const pn.PaddleOcrConfig(),
      engine: const pn.EngineConfig(numThreads: 4),
    );
    final croppedFile = await _saveBytesToFile(cropped, 'repl_main.jpg');
    final rightFile = rightPart != null ? await _saveBytesToFile(rightPart, 'repl_right.jpg') : null;
    final iconFile = iconPart != null ? await _saveBytesToFile(iconPart, 'repl_icon.jpg') : null;
    final run = await ocr.recognize(croppedFile.path);
    final rightRun = rightFile != null ? await ocr.recognize(rightFile.path) : null;
    final iconRun = iconFile != null ? await ocr.recognize(iconFile.path) : null;
    await ocr.dispose();
    final results = run.results;
    final rightResults = rightRun?.results ?? <pn.OcrResult>[];
    final iconResults = iconRun?.results ?? <pn.OcrResult>[];
    final parsed = ArtifactParser.parse(results, rightBlocks: rightResults, iconBlocks: iconResults);
    return 'MAIN: ${parsed['main_stat']}\nDOP: ${parsed['dop_stats']}';
  }

  Uint8List? _cropRightPart(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final cropped = img.copyCrop(decoded, x: 252, y: 445, width: 380 - 252, height: 488 - 445);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  }

  Uint8List? _cropIcon(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final iconX = _prefsCache?.getInt('icon_x') ?? 91;
    final iconY = _prefsCache?.getInt('icon_y') ?? 393;
    final iconW = _prefsCache?.getInt('icon_w') ?? 70;
    final iconH = _prefsCache?.getInt('icon_h') ?? 70;
    final cropped = img.copyCrop(decoded, x: iconX, y: iconY, width: iconW, height: iconH);
    final iconScale = _prefsCache?.getInt('icon_scale') ?? 4;
    final enlarged = img.copyResize(
      cropped,
      width: iconW * iconScale,
      height: iconH * iconScale,
      interpolation: img.Interpolation.cubic,
    );
    try {
      final dir = Directory('${Directory.systemTemp.path}/dataset_icons');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final f = File('${dir.path}/icon_$ts.jpg');
      f.writeAsBytesSync(img.encodeJpg(enlarged, quality: 100));
      _dprint("[DATASET] saved: ${f.path}");
    } catch (e) {
      _dprint("[DATASET] err: $e");
    }
    return Uint8List.fromList(img.encodeJpg(enlarged, quality: 95));
  }

  int? _detectRank(Uint8List bytes) {
    final cropped = img.decodeImage(bytes);
    if (cropped == null) return null;
    final lumThreshold = _prefsCache?.getInt('rank_lum') ?? 40;
    final minCount = _prefsCache?.getInt('rank_min_count') ?? 10;
    int rSum = 0, gSum = 0, bSum = 0, count = 0;
    for (int y = 0; y < cropped.height; y++) {
      for (int x = 0; x < cropped.width; x++) {
        final p = cropped.getPixel(x, y);
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final lum = (r + g + b) / 3;
        if (lum > lumThreshold) { rSum += r; gSum += g; bSum += b; count++; }
      }
    }
    if (count < minCount) return null;
    final avgR = rSum / count;
    final avgG = gSum / count;
    final avgB = bSum / count;
    final r6 = _prefsCache?.getInt('rank_red_r') ?? 200;
    final g6 = _prefsCache?.getInt('rank_red_g') ?? 100;
    final b6 = _prefsCache?.getInt('rank_red_b') ?? 100;
    final r5 = _prefsCache?.getInt('rank_orange_r') ?? 200;
    final g5 = _prefsCache?.getInt('rank_orange_g') ?? 130;
    final b5 = _prefsCache?.getInt('rank_orange_b') ?? 100;
    final r4 = _prefsCache?.getInt('rank_purple_r') ?? 150;
    final g4 = _prefsCache?.getInt('rank_purple_g') ?? 100;
    final b4 = _prefsCache?.getInt('rank_purple_b') ?? 150;
    final r1 = _prefsCache?.getInt('rank_gray_r') ?? 180;
    final g1 = _prefsCache?.getInt('rank_gray_g') ?? 180;
    final b1 = _prefsCache?.getInt('rank_gray_b') ?? 180;
    if (avgR > r6 && avgG < g6 && avgB < b6) return 6;
    if (avgR > r5 && avgG > g5 && avgB < b5) return 5;
    if (avgR > r4 && avgB > b4 && avgG < g4 + 40) return 4;
    if (avgB > avgR && avgB > avgG) return 3;
    if (avgG > avgR && avgG > avgB) return 2;
    if (avgR > r1 && avgG > g1 && avgB > b1) return 1;
    return 5;
  }

  Future<Uint8List?> _cropBottomLeft(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final cx = prefs.getInt("crop_x") ?? 50;
    final cy = prefs.getInt("crop_y") ?? 352;
    final cw = prefs.getInt("crop_w") ?? 470;
    final ch = prefs.getInt("crop_h") ?? 358;
    final cropped = img.copyCrop(decoded, x: cx, y: cy, width: cw, height: ch);
    final scale = prefs.getInt("crop_scale") ?? 3;
    final resized = img.copyResize(cropped, width: cropped.width * scale);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 95));
  }

  Future<File> _saveBytesToFile(Uint8List bytes, String name) async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _runOcr(Uint8List? cropped, Uint8List? rightPart, Uint8List? iconPart) async {
    if (cropped == null) return;
    try {
      final ocr = pn.PaddleOcr();
      await ocr.init(
        config: const pn.PaddleOcrConfig(),
        engine: const pn.EngineConfig(numThreads: 4),
      );
      final croppedFile = await _saveBytesToFile(cropped, 'main_crop.jpg');
      final rightFile = rightPart != null ? await _saveBytesToFile(rightPart, 'right_crop.jpg') : null;
      final iconFile = iconPart != null ? await _saveBytesToFile(iconPart, 'icon_crop.jpg') : null;
      final run = await ocr.recognize(croppedFile.path);
      final rightRun = rightFile != null ? await ocr.recognize(rightFile.path) : null;
      final iconRun = iconFile != null ? await ocr.recognize(iconFile.path) : null;
      await ocr.dispose();
      final results = run.results;
      final rightResults = rightRun?.results ?? <pn.OcrResult>[];
      final iconResults = iconRun?.results ?? <pn.OcrResult>[];

      String? detectedRank;
      if (iconPart != null) {
        detectedRank = _detectRank(iconPart)?.toString();
      }

      final prefsNow = await SharedPreferences.getInstance();
      final overrideRank = prefsNow.getInt('rank') ?? 0;
      final finalRank = (overrideRank >= 1 && overrideRank <= 6) ? overrideRank : detectedRank;

      final parsed = ArtifactParser.parse(results, rightBlocks: rightResults, iconBlocks: iconResults);
      if (finalRank != null) parsed['rank'] = finalRank;

      _dprint("[GameValidator] START");
      final validationNotes = GameValidator.validate(parsed);
      _dprint('[GameValidator] DONE');
      for (final note in validationNotes) {
        _dprint('[GameValidator] $note');
      }

      final text = results.map((r) => r.text).join("\n") + "\n" + rightResults.map((r) => r.text).join("\n");
      final rank = int.tryParse(parsed['rank']?.toString() ?? '');
      final rankStr = rank != null ? '$rank★' : '?★';

      final setStr = parsed['set'] ?? '?';
      final typeStr = parsed['type'] ?? '?';
      final rarityStr = parsed['rarity'] ?? '?';
      final levelStr = parsed['level'] != null ? '+${parsed['level']}' : '?';

      final header = '🎯 $setStr ($typeStr)';
      final subheader = '$rankStr $rarityStr | $levelStr';

      // MAIN
      final mainStat = parsed['main_stat'] as Map<String, dynamic>? ?? {};
      final mainLinesNew = <String>[];
      if (mainStat['name'] != null && mainStat['value'] != null) {
        mainLinesNew.add('${mainStat['name']}|${mainStat['value']}${mainStat['isPercent'] == true ? '%' : ''}');
      }

      // DOP из всех трех корзин
      final statsMap = parsed['stats'] as Map<String, List<int>>? ?? {};
      final percentMap = parsed['stats_percent'] as Map<String, List<int>>? ?? {};
      final dopMap = parsed['dop_stats'] as Map<String, List<int>>? ?? {};
      final dopLinesNew = <String>[];
      percentMap.forEach((k, v) {
        if (k != mainStat['name'] || v.first != mainStat['value']) {
          dopLinesNew.add('$k|${v.first}%');
        }
      });
      statsMap.forEach((k, v) {
        if (k != mainStat['name'] || v.first != mainStat['value']) {
          dopLinesNew.add('$k|${v.first}');
        }
      });
      dopMap.forEach((k, v) {
        if (k != mainStat['name'] || v.first != mainStat['value']) {
          dopLinesNew.add('$k|${v.first}');
        }
      });

      // 🔥 ГЛИФЫ С ПРОЦЕНТАМИ
      final glyphs = parsed['glyphs'] as Map<String, List<int>>? ?? {};
      final glyphPercents = parsed['glyph_percents'] as Map<String, bool>? ?? {};
      final glyphLinesNew = <String>[];
      glyphs.forEach((k, v) {
        final pct = glyphPercents[k] == true ? '%' : '';
        glyphLinesNew.add('$k|+${v.first}$pct');
      });

      final bonusStr = parsed['set_bonus'] ?? '?';
      final wornStr = parsed['worn'] != null ? '👤 Надето: ${parsed['worn']}' : '';

      final parsedData = [
        header,
        subheader,
        mainLinesNew.join(','),
        dopLinesNew.join(','),
        glyphLinesNew.join(','),
        bonusStr,
        wornStr,
      ].join('|||');

      setState(() {
        _ocrText = text;
        _parsedText = parsedData;
        _debugLog = _debugBuffer.join('\n');
        _status = 'OCR и парсинг завершены!';
      });
    } catch (e) {
      setState(() => _status = 'Ошибка OCR: $e');
    }
  }

  void _debugPrintBlock(String tag, int i, pn.OcrResult r) {
    if (r.points.isEmpty) return;
  }

  Future<void> _exportDataset() async {
    try {
      final srcDir = Directory('${Directory.systemTemp.path}/dataset_icons');
      if (!srcDir.existsSync()) {
        setState(() => _status = 'Нет кропов для экспорта');
        return;
      }
      final dstDir = Directory('/storage/emulated/0/Download/raid_dataset');
      if (!dstDir.existsSync()) dstDir.createSync(recursive: true);
      int count = 0;
      for (final file in srcDir.listSync()) {
        if (file is File && file.path.endsWith('.jpg')) {
          final name = file.path.split('/').last;
          file.copySync('${dstDir.path}/$name');
          count++;
        }
      }
      setState(() => _status = 'Экспортировано $count кропов в Download/raid_dataset');
    } catch (e) {
      setState(() => _status = 'Ошибка экспорта: $e');
    }
  }

  Widget _buildNewCard(String data) {
    final parts = data.split('|||');
    if (parts.length < 7) return const Text('Ошибка формата данных');

    final header = parts[0];
    final subheader = parts[1];
    final mainStr = parts[2];
    final dopStr = parts[3];
    final glyphStr = parts[4];
    final bonusStr = parts[5];
    final wornStr = parts[6];

    List<Widget> parseStats(String raw, bool isGlyph) {
      if (raw.isEmpty) return [];
      return raw.split(',').map((line) {
        final kv = line.split('|');
        if (kv.length < 2) return const SizedBox.shrink();
        final k = kv[0];
        final v = kv[1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Row(
            children: [
              Text(k, style: const TextStyle(color: Colors.white, fontSize: 14)),
              Expanded(
                child: Text(
                  ' .................... ',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(color: Colors.grey[700], fontSize: 14, letterSpacing: 1.0),
                ),
              ),
              Text(v, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }).toList();
    }

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.blueGrey, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(header, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 2),
            Text(subheader, style: const TextStyle(fontSize: 14, color: Colors.amber, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_croppedBytes != null)
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_croppedBytes!, width: 110)),
                const SizedBox(width: 10),
                if (_iconBytes != null)
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_iconBytes!, width: 110)),
              ],
            ),
            const Divider(color: Colors.blueGrey, height: 20),
            const Text('💥 MAIN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber)),
            const SizedBox(height: 6),
            ...parseStats(mainStr, false),
            if (dopStr.isNotEmpty) ...[
              const Divider(color: Colors.blueGrey, height: 20),
              const Text('📊 SUBSTATS (DOP)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber)),
              const SizedBox(height: 6),
              ...parseStats(dopStr, false),
            ],
            if (glyphStr.isNotEmpty) ...[
              const Divider(color: Colors.blueGrey, height: 20),
              const Text('✨ ГЛИФЫ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber)),
              const SizedBox(height: 6),
              ...parseStats(glyphStr, true),
            ],
            const Divider(color: Colors.blueGrey, height: 20),
            const Text('📦 БОНУС СЕТА', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber)),
            const SizedBox(height: 6),
            Text(bonusStr, style: const TextStyle(color: Colors.white, fontSize: 14)),
            if (wornStr.isNotEmpty) ...[
              const Divider(color: Colors.blueGrey, height: 20),
              Text(wornStr, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raid Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_library),
                label: const Text('Выбрать видео'),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PolygonOcrDiagnosticScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.fact_check),
                      label: const Text('Эталонный OCR-тест (speed_ru)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade100,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _testOnnx,
                      icon: const Icon(Icons.memory),
                      label: const Text('Тест ONNX'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                    ),

                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_lastFrame == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Сначала выбери видео')),
                          );
                          return;
                        }
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CropCalibrator(frameBytes: _lastFrame),
                        ));
                      },
                      icon: const Icon(Icons.crop),
                      label: const Text('Калибратор'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade100),
                    ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReplScreen(onParse: parseCurrent)),
                  );
                },
                icon: const Icon(Icons.terminal),
                label: const Text('REPL'),
                    ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _exportDataset,
                icon: const Icon(Icons.save_alt),
                label: const Text('Экспорт датасета'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade100),
                    ),
                    const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _debugLog));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Лог скопирован!')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Скопировать лог'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade100),
              ),
              const SizedBox(height: 20),
              Text(_status, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              if (_croppedBytes != null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Image.memory(_croppedBytes!, width: 200),
                ),
              if (_iconBytes != null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text('ICON CROP:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Image.memory(_iconBytes!, width: 150),
                    ],
                  ),
                ),
              if (_parsedText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildNewCard(_parsedText),
                ),
              if (_debugLog.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black12,
                    child: Text('DEBUG LOG:\n$_debugLog', style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class CropCalibrator extends StatefulWidget {
  final Uint8List? frameBytes;
  const CropCalibrator({super.key, this.frameBytes});

  @override
  State<CropCalibrator> createState() => _CropCalibratorState();
}

class _CropCalibratorState extends State<CropCalibrator> {
  Offset? _topLeft;
  Offset? _bottomRight;
  final _imageKey = GlobalKey();

  Future<void> _save() async {
    if (_topLeft == null || _bottomRight == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Поставь 2 точки!')),
      );
      return;
    }

    final bytes = widget.frameBytes;
    if (bytes == null) return;

    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось декодировать кадр')),
      );
      return;
    }

    final realW = decoded.width.toDouble();
    final realH = decoded.height.toDouble();
    final boxSize = box.size;

    if (boxSize.width <= 0 || boxSize.height <= 0) return;

    final boxRatio = boxSize.width / boxSize.height;
    final imageRatio = realW / realH;

    double displayedW;
    double displayedH;
    double dx = 0;
    double dy = 0;

    if (imageRatio > boxRatio) {
      displayedW = boxSize.width;
      displayedH = boxSize.width / imageRatio;
      dy = (boxSize.height - displayedH) / 2;
    } else {
      displayedH = boxSize.height;
      displayedW = boxSize.height * imageRatio;
      dx = (boxSize.width - displayedW) / 2;
    }

    bool insideImage(Offset point) {
      return point.dx >= dx &&
          point.dx <= dx + displayedW &&
          point.dy >= dy &&
          point.dy <= dy + displayedH;
    }

    if (!insideImage(_topLeft!) || !insideImage(_bottomRight!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Точки должны находиться внутри изображения'),
        ),
      );
      return;
    }

    if (_bottomRight!.dx <= _topLeft!.dx ||
        _bottomRight!.dy <= _topLeft!.dy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вторая точка должна быть правее и ниже первой'),
        ),
      );
      return;
    }

    final x = ((_topLeft!.dx - dx) / displayedW * realW)
        .round().clamp(0, decoded.width).toInt();
    final y = ((_topLeft!.dy - dy) / displayedH * realH)
        .round().clamp(0, decoded.height).toInt();

    final right = ((_bottomRight!.dx - dx) / displayedW * realW)
        .round().clamp(0, decoded.width).toInt();
    final bottom = ((_bottomRight!.dy - dy) / displayedH * realH)
        .round().clamp(0, decoded.height).toInt();

    final w = right - x;
    final h = bottom - y;

    if (w <= 0 || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Получилась пустая область')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('crop_x', x);
    await prefs.setInt('crop_y', y);
    await prefs.setInt('crop_w', w);
    await prefs.setInt('crop_h', h);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сохранено: x=$x y=$y w=$w h=$h')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Калибратор'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _save),
        ],
      ),
      body: widget.frameBytes == null
          ? const Center(child: Text('Нет кадра'))
          : LayoutBuilder(
              builder: (context, c) => GestureDetector(
                onTapDown: (d) {
                  setState(() {
                    if (_topLeft == null || (_topLeft != null && _bottomRight != null)) {
                      _topLeft = d.localPosition;
                      _bottomRight = null;
                    } else {
                      _bottomRight = d.localPosition;
                    }
                  });
                },
                child: Stack(
                  key: _imageKey,
                  children: [
                    Image.memory(widget.frameBytes!, fit: BoxFit.contain, width: c.maxWidth, height: c.maxHeight),
                    if (_topLeft != null)
                      Positioned(left: _topLeft!.dx - 10, top: _topLeft!.dy - 10,
                        child: Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)))),
                    if (_bottomRight != null)
                      Positioned(left: _bottomRight!.dx - 10, top: _bottomRight!.dy - 10,
                        child: Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(10)))),
                    if (_topLeft != null && _bottomRight != null)
                      Positioned(left: _topLeft!.dx, top: _topLeft!.dy,
                        child: Container(width: _bottomRight!.dx - _topLeft!.dx, height: _bottomRight!.dy - _topLeft!.dy,
                          decoration: BoxDecoration(border: Border.all(color: Colors.yellow, width: 2)))),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _topLeft == null ? 'Тап 1: верхний-левый угол' : _bottomRight == null ? 'Тап 2: нижний-правый угол' : 'Готово! Жми "Сохранить"',
          style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
      ),
    );
  }
}

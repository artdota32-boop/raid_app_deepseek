import sys
import inspect
from pathlib import Path
import cv2

BASE = Path("experiments/card_localization").resolve()
sys.path.insert(0, str(BASE))

import test_dbnet_on_samples as test

image_path = BASE / "dbnet_samples_v1/card_001_t0p6s.jpg"
image = cv2.imread(str(image_path))

if image is None:
    raise SystemExit("ОШИБКА: образец не найден")

tensor = test.detector.dbnet_preprocess(image)

print("=== ФУНКЦИЯ ПРЕДОБРАБОТКИ ===")
print(inspect.getsource(test.detector.dbnet_preprocess))

print("=== ФАКТИЧЕСКИЙ ФОРМАТ ТЕНЗОРА ===")
print("Тип:", type(tensor))
print("Форма:", getattr(tensor, "shape", "нет атрибута shape"))
print("Тип элементов:", getattr(tensor, "dtype", "нет атрибута dtype"))

if isinstance(tensor, (list, tuple)):
    print("Количество элементов:", len(tensor))
    for i, item in enumerate(tensor):
        print(f"Элемент {i}: тип={type(item)}, форма={getattr(item, 'shape', 'нет shape')}")

print("=== ВХОД ONNX ===")
session = test.ort.InferenceSession(
    str(test.detector.MODEL_PATH),
    providers=["CPUExecutionProvider"]
)
for item in session.get_inputs():
    print("Имя:", item.name)
    print("Форма:", item.shape)
    print("Тип:", item.type)

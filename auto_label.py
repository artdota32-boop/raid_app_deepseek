import requests
import json

API_KEY = "6hTORjoSoDnu6QpsoDJD"
PROJECT_NAME = "raid_stars"
WORKSPACE_ID = "arturs-workspace-qi0u7"

# 1. Получаем список картинок
print("📡 Получаю список картинок...")
url = f"https://api.roboflow.com/{WORKSPACE_ID}/{PROJECT_NAME}/search?api_key={API_KEY}"
response = requests.get(url)
if response.status_code != 200:
    print(f"❌ Ошибка: {response.text}")
    exit()

data = response.json()
images = data.get("results", [])
print(f"✅ Найдено картинок: {len(images)}")

# 2. Создаем классы (если их нет)
print("📝 Создаю классы...")
classes_url = f"https://api.roboflow.com/{WORKSPACE_ID}/{PROJECT_NAME}/classes?api_key={API_KEY}"
for cls_name in ["5star", "6star"]:
    r = requests.post(classes_url, json={"name": cls_name})
    if r.status_code in [200, 201]:
        print(f"  ✅ Класс {cls_name} создан")
    else:
        print(f"  ℹ️ Класс {cls_name} уже есть или ошибка: {r.status_code}")

print("\n⚠️ Готово. Теперь надо разметить вручную через API, это чуть сложнее.")
print("Но пока проверь, что скрипт работает — увидел картинки?")

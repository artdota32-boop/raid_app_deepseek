with open('.github/workflows/build.yml', 'r') as f:
    content = f.read()

# Блок очистки
clean_step = """      # --- ОЧИСТКА ДИСКА ---
      - name: Free Disk Space
        uses: jlumbroso/free-disk-space@main
        with:
          tool-cache: false
          android: true
          dotnet: true
          haskell: true
          large-packages: true
          docker-images: true
          swap-storage: true
      # --- КОНЕЦ ОЧИСТКИ ---
"""

# Вставляем сразу после "steps:"
if "Free Disk Space" not in content:
    content = content.replace("steps:\n", "steps:\n" + clean_step, 1)
    with open('.github/workflows/build.yml', 'w') as f:
        f.write(content)
    print("✅ Блок очистки диска добавлен в build.yml!")
else:
    print("✅ Блок очистки уже есть в build.yml!")

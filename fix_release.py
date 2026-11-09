with open('.github/workflows/build.yml', 'r') as f:
    content = f.read()

# Ищем блок Upload APK и заменяем его на создание релиза
old_block = """      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: raid-app-onnx
          path: build/app/outputs/flutter-apk/app-debug.apk
          retention-days: 1
          compression-level: 0"""

new_block = """      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/app/outputs/flutter-apk/app-debug.apk
          tag_name: build-${{ github.run_number }}
          name: Raid Scanner Build ${{ github.run_number }}
          draft: false
          prerelease: false"""

if "softprops/action-gh-release" not in content:
    content = content.replace(old_block, new_block)
    with open('.github/workflows/build.yml', 'w') as f:
        f.write(content)
    print("✅ build.yml обновлен: теперь APK летит в Releases!")
else:
    print("✅ Блок Releases уже установлен.")

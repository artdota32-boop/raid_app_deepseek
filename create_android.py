import os

dirs = [
    "android/app/src/main/kotlin/com/example/raid_app",
    "android/app/src/main/res/values",
    "android/app/src/main/res/drawable",
    "android/app/src/main/res/mipmap-hdpi"
]

for d in dirs:
    os.makedirs(d, exist_ok=True)

manifest = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="Raid Scanner"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>"""

main_activity = """package com.example.raid_app

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
}"""

styles = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>"""

launch_bg = """<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/white" />
</layer-list>"""

with open("android/app/src/main/AndroidManifest.xml", "w") as f: f.write(manifest)
with open("android/app/src/main/kotlin/com/example/raid_app/MainActivity.kt", "w") as f: f.write(main_activity)
with open("android/app/src/main/res/values/styles.xml", "w") as f: f.write(styles)
with open("android/app/src/main/res/drawable/launch_background.xml", "w") as f: f.write(launch_bg)

print("✅ Структура Android создана успешно!")

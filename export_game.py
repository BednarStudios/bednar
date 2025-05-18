import subprocess
import sys
import os

GODOT_PATH = "/caminho/para/godot"

PROJECT_PATH = os.path.abspath(".")

EXPORT_OUTPUT = os.path.join(PROJECT_PATH, "build/bednar.exe")

EXPORT_PRESET = "Windows"

def export_game():
    result = subprocess.run([
        GODOT_PATH,
        "--headless",
        "--export-release",
        EXPORT_PRESET,
        EXPORT_OUTPUT
    ])

    if result.returncode == 0:
      pass
    else:
        sys.exit(result.returncode)

if __name__ == "__main__":
    export_game()

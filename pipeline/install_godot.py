import urllib.request
import zipfile
import os

url = "https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_win64.exe.zip"
tools_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "godot")
os.makedirs(tools_dir, exist_ok=True)
zip_path = os.path.join(tools_dir, "godot.zip")

print("Downloading Godot 4.3 from:", url)
urllib.request.urlretrieve(url, zip_path)
print("Extracting Godot 4.3 to:", tools_dir)
with zipfile.ZipFile(zip_path, 'r') as zip_ref:
    zip_ref.extractall(tools_dir)
os.remove(zip_path)
print("Godot 4.3 setup completed successfully.")

import zipfile
import os

def zip_build_folder(build_path: str, output_zip: str):
    with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(build_path):
            for file in files:
                file_path = os.path.join(root, file)
                zipf.write(file_path, os.path.relpath(file_path, build_path))

if __name__ == "__main__":
    build_folder = "build/"
    output_zip = "bednar_build.zip"
    zip_build_folder(build_folder, output_zip)
    print(f"Build zipado em: {output_zip}")

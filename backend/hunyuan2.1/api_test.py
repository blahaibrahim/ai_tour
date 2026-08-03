import requests
import os

api_url = "https://blahaibrahim--hunyuan3d-api-generate-3d-api.modal.run"

# Use the test image from the project root
test_image_path = os.path.join(os.path.dirname(__file__), "..", "..", "test.jpg")
test_image_path = os.path.abspath(test_image_path)

print(f"Sending image: {test_image_path}")

with open(test_image_path, "rb") as f:
    response = requests.post(
        api_url,
        files={"file": ("test.jpg", f, "image/jpeg")}
    )

print(f"Status code: {response.status_code}")

if response.status_code == 200:
    data = response.json()
    print(f"Success! Response: {data}")

    signed_url = data.get("signed_url", "")
    storage_path = data.get("storage_path", "unknown")
    file_size = data.get("file_size_bytes", 0)

    print(f"Supabase Storage path: {storage_path}")
    print(f"File size: {file_size:,} bytes")
    print(f"Signed URL: {signed_url}")

    if signed_url:
        print("Downloading .glb from signed URL...")
        download_response = requests.get(signed_url)

        if download_response.status_code == 200:
            # Save to project root
            output_path = os.path.join(os.path.dirname(__file__), "..", "..", "result.glb")
            output_path = os.path.abspath(output_path)

            with open(output_path, "wb") as out_file:
                out_file.write(download_response.content)

            print(f"3D Model saved locally at: {output_path}")
            print(f"Local file size: {len(download_response.content):,} bytes")
        else:
            print(f"Failed to download from signed URL: {download_response.status_code}")
    else:
        print("No signed URL returned — cannot download locally.")
else:
    print(f"Generation failed: {response.status_code}")
    print(response.text)
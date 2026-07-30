import requests

api_url = "https://blahaibrahim--hunyuan3d-api-generate-3d-api.modal.run"

with open("test.jpg", "rb") as f:
    response = requests.post(api_url, files={"file": f})

if response.status_code == 200:
    with open("result.glb", "wb") as f:
        f.write(response.content)
    print("3D Model downloaded successfully!")
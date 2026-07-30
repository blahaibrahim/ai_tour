import modal
import subprocess
import os
from fastapi import UploadFile, File, Response

app = modal.App("hunyuan3d-api")

# We need the u2net cache back for the background remover!
hf_cache = modal.Volume.from_name("hf-cache")
hy3dgen_cache = modal.Volume.from_name("hy3dgen-cache")
u2net_cache = modal.Volume.from_name("u2net-cache", create_if_missing=True)

image = (
    modal.Image.from_dockerfile("Dockerfile")
    .pip_install("fastapi", "python-multipart")
)

@app.function(
    image=image, 
    gpu="L4", 
    timeout=3600,
    max_containers=1, 
    volumes={
        "/root/.cache/huggingface": hf_cache,
        "/root/.cache/hy3dgen": hy3dgen_cache,
        "/root/.u2net": u2net_cache
    }
)
@modal.fastapi_endpoint(method="POST")
async def generate_3d_api(file: UploadFile = File(...)):
    print(f"API Request received! Processing image: {file.filename}")
    
    image_bytes = await file.read()
    
    # Paths
    raw_input_path = "/workspace/Hunyuan3D-2.1/assets/raw_input.jpg"
    output_glb = "/workspace/Hunyuan3D-2.1/demo_textured.glb"
    
    if os.path.exists(output_glb):
        os.remove(output_glb)
        
    os.makedirs(os.path.dirname(raw_input_path), exist_ok=True)
    with open(raw_input_path, "wb") as f:
        f.write(image_bytes)
        
    print("Running Custom Pipeline...")
    
    # Here is your custom Python script that runs inside the Conda environment
    cmd = """
    source /workspace/miniconda3/bin/activate hunyuan3d21
    pip install "setuptools<70.0.0" -q
    cd /workspace/Hunyuan3D-2.1
    
    cat << 'EOF' > custom_pipeline.py
import sys
import os
from PIL import Image

# ---------------------------------------------------------
# STEP 1: YOUR CUSTOM BACKGROUND REMOVAL
# ---------------------------------------------------------
print("--- STEP 1: Removing Background ---")
from rembg import remove, new_session

input_img = Image.open('assets/raw_input.jpg')

# You can change 'u2net' to 'isnet-general-use' for better quality if needed
session = new_session("u2net")
transparent_img = remove(input_img, session=session)

# PRO TIP: Crop the image to the bounding box of the object. 
# This removes the floor/desk shadows and fixes the "flat base" issue you saw earlier!
bbox = transparent_img.getbbox()
if bbox:
    transparent_img = transparent_img.crop(bbox)

transparent_img.save('assets/processed.png')
print("Background removed and cropped successfully.")

# ---------------------------------------------------------
# STEP 2: 3D GENERATION
# ---------------------------------------------------------
print("--- STEP 2: Generating 3D Model ---")
sys.path.insert(0, './hy3dshape')
sys.path.insert(0, './hy3dpaint')
from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
from textureGenPipeline import Hunyuan3DPaintPipeline, Hunyuan3DPaintConfig

try:
    from torchvision_fix import apply_fix
    apply_fix()
except:
    pass

# Generate Shape
pipeline_shapegen = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained('tencent/Hunyuan3D-2.1')
img_for_3d = Image.open('assets/processed.png').convert("RGBA")
mesh = pipeline_shapegen(image=img_for_3d)[0]
mesh.export('demo.glb')

# Paint Textures
conf = Hunyuan3DPaintConfig(6, 512)
conf.realesrgan_ckpt_path = "hy3dpaint/ckpt/RealESRGAN_x4plus.pth"
conf.multiview_cfg_path = "hy3dpaint/cfgs/hunyuan-paint-pbr.yaml"
conf.custom_pipeline = "hy3dpaint/hunyuanpaintpbr"
paint_pipeline = Hunyuan3DPaintPipeline(conf)

paint_pipeline(mesh_path="demo.glb", image_path='assets/processed.png', output_mesh_path='demo_textured.glb')
EOF
    
    # Execute the custom pipeline
    python custom_pipeline.py
    """
    
    subprocess.run(cmd, shell=True, executable="/bin/bash")
    
    if not os.path.exists(output_glb):
        return Response(content="Generation failed", status_code=500)
        
    with open(output_glb, "rb") as f:
        glb_bytes = f.read()
        
    print("Generation complete! Sending .glb back to client.")
    return Response(content=glb_bytes, media_type="model/gltf-binary")
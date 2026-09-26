#!/usr/bin/env python3
"""Generate a ~5 s video with audio on the 3090 via ComfyUI + LTX-2.3 (GGUF).

Text-to-video:   ltx-video.py --prompt "..." --out fox.mp4
Image-to-video:  ltx-video.py --prompt "..." --image still.png --out clip.mp4

Talks only to the ollama-gateway (default http://127.0.0.1:8188), whose
comfy_filter takes a gpu-yield lease: Ollama is unloaded, Forge's RAM freed,
and the job is refused (503) if the host lacks RAM. Needs the `video` compose
profile running. Mirrors the official LTX-2.3 two-stage template: 8 distilled
steps at half resolution, 2x latent upscale, 3 refine steps. Stdlib only.

Prompting: describe the action as it unfolds, the camera move, and the sound
(LTX generates audio in the same pass).
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request, uuid

UNET = "ltx-2.3-22b-distilled-1.1-Q4_K_M.gguf"
TE = "gemma-3-12b-it-abliterated-Q4_K_M.gguf"
CONNECTORS = "ltx-2.3-22b-distilled_embeddings_connectors.safetensors"
VIDEO_VAE = "ltx-2.3-22b-distilled_video_vae.safetensors"
AUDIO_VAE = "ltx-2.3-22b-distilled_audio_vae.safetensors"
UPSCALER = "ltx-2.3-spatial-upscaler-x2-1.1.safetensors"
NEG = "pc game, console game, video game, cartoon, childish, ugly, blurry, static, frozen, distorted anatomy"


def graph(prompt, negative, seed, width, height, frames, fps, image, prefix):
    i2v = image is not None
    img = ({"class_type": "LoadImage", "inputs": {"image": image}} if i2v else
           {"class_type": "EmptyImage", "inputs": {"width": width, "height": height, "batch_size": 1, "color": 0}})
    return {
        "img": img,
        "pre": {"class_type": "LTXVPreprocess", "inputs": {"image": ["img", 0], "img_compression": 18}},
        "unet": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": UNET}},
        "clip": {"class_type": "DualCLIPLoaderGGUF", "inputs": {"clip_name1": TE, "clip_name2": CONNECTORS, "type": "ltxv"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": VIDEO_VAE}},
        "avae": {"class_type": "LTXVAudioVAELoader", "inputs": {"ckpt_name": AUDIO_VAE}},
        "pos": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["clip", 0]}},
        "neg": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": ["clip", 0]}},
        "cond": {"class_type": "LTXVConditioning", "inputs": {"positive": ["pos", 0], "negative": ["neg", 0], "frame_rate": float(fps)}},
        # Stage 1: half resolution, image-conditioned at 0.7 (bypassed for text-to-video).
        "lat1": {"class_type": "EmptyLTXVLatentVideo", "inputs": {"width": width // 2, "height": height // 2, "length": frames, "batch_size": 1}},
        "i2v1": {"class_type": "LTXVImgToVideoInplace", "inputs": {"vae": ["vae", 0], "image": ["pre", 0], "latent": ["lat1", 0], "strength": 0.7, "bypass": not i2v}},
        "alat": {"class_type": "LTXVEmptyLatentAudio", "inputs": {"frames_number": frames, "frame_rate": fps, "batch_size": 1, "audio_vae": ["avae", 0]}},
        "av1": {"class_type": "LTXVConcatAVLatent", "inputs": {"video_latent": ["i2v1", 0], "audio_latent": ["alat", 0]}},
        "noise1": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "samp": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "sig1": {"class_type": "ManualSigmas", "inputs": {"sigmas": "1.0, 0.99375, 0.9875, 0.98125, 0.975, 0.909375, 0.725, 0.421875, 0.0"}},
        "guide1": {"class_type": "CFGGuider", "inputs": {"model": ["unet", 0], "positive": ["cond", 0], "negative": ["cond", 1], "cfg": 1.0}},
        "s1": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["noise1", 0], "guider": ["guide1", 0], "sampler": ["samp", 0], "sigmas": ["sig1", 0], "latent_image": ["av1", 0]}},
        "sep1": {"class_type": "LTXVSeparateAVLatent", "inputs": {"av_latent": ["s1", 0]}},
        # Stage 2: 2x latent upscale, re-inject the image, 3 refine steps.
        "upm": {"class_type": "LatentUpscaleModelLoader", "inputs": {"model_name": UPSCALER}},
        "up": {"class_type": "LTXVLatentUpsampler", "inputs": {"samples": ["sep1", 0], "upscale_model": ["upm", 0], "vae": ["vae", 0]}},
        "i2v2": {"class_type": "LTXVImgToVideoInplace", "inputs": {"vae": ["vae", 0], "image": ["pre", 0], "latent": ["up", 0], "strength": 1.0, "bypass": not i2v}},
        "av2": {"class_type": "LTXVConcatAVLatent", "inputs": {"video_latent": ["i2v2", 0], "audio_latent": ["sep1", 1]}},
        "crop": {"class_type": "LTXVCropGuides", "inputs": {"positive": ["cond", 0], "negative": ["cond", 1], "latent": ["sep1", 0]}},
        "guide2": {"class_type": "CFGGuider", "inputs": {"model": ["unet", 0], "positive": ["crop", 0], "negative": ["crop", 1], "cfg": 1.0}},
        "noise2": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed + 1}},
        "sig2": {"class_type": "ManualSigmas", "inputs": {"sigmas": "0.85, 0.7250, 0.4219, 0.0"}},
        "s2": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["noise2", 0], "guider": ["guide2", 0], "sampler": ["samp", 0], "sigmas": ["sig2", 0], "latent_image": ["av2", 0]}},
        "sep2": {"class_type": "LTXVSeparateAVLatent", "inputs": {"av_latent": ["s2", 0]}},
        "dec": {"class_type": "VAEDecodeTiled", "inputs": {"samples": ["sep2", 0], "vae": ["vae", 0], "tile_size": 768, "overlap": 64, "temporal_size": 4096, "temporal_overlap": 4}},
        "adec": {"class_type": "LTXVAudioVAEDecode", "inputs": {"samples": ["sep2", 1], "audio_vae": ["avae", 0]}},
        "vid": {"class_type": "CreateVideo", "inputs": {"images": ["dec", 0], "fps": float(fps), "audio": ["adec", 0]}},
        "save": {"class_type": "SaveVideo", "inputs": {"video": ["vid", 0], "filename_prefix": prefix, "format": "auto", "codec": "auto"}},
    }


def request(url, data=None, headers=None, timeout=180):
    req = urllib.request.Request(url, data, headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def upload(base, path):
    boundary = uuid.uuid4().hex
    name = f"ltx_{uuid.uuid4().hex[:8]}{os.path.splitext(path)[1] or '.png'}"
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{name}\"\r\n"
            f"Content-Type: application/octet-stream\r\n\r\n").encode() + open(path, "rb").read() + \
           f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--{boundary}--\r\n".encode()
    out = json.loads(request(base + "/upload/image", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"}))
    return out["name"]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--negative", default=NEG)
    ap.add_argument("--image", help="start frame for image-to-video; output keeps its framing")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=int(time.time()) % 2**31)
    ap.add_argument("--width", type=int, default=1216, help="multiple of 64")
    ap.add_argument("--height", type=int, default=832, help="multiple of 64")
    ap.add_argument("--frames", type=int, default=121, help="8k+1; 121 = 5 s at 24 fps; quality drops past ~161")
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--comfy", default=os.environ.get("COMFY", "http://127.0.0.1:8188"))
    a = ap.parse_args()
    if a.width % 64 or a.height % 64 or (a.frames - 1) % 8:
        sys.exit("width/height must be multiples of 64 and frames must be 8k+1")

    image = upload(a.comfy, a.image) if a.image else None
    prefix = f"ltx_{uuid.uuid4().hex[:8]}"
    wf = graph(a.prompt, a.negative, a.seed, a.width, a.height, a.frames, a.fps, image, prefix)
    t = time.time()
    try:
        pid = json.loads(request(a.comfy + "/prompt", json.dumps({"prompt": wf}).encode(),
                                 {"Content-Type": "application/json"}))["prompt_id"]
    except urllib.error.HTTPError as e:
        sys.exit(f"refused ({e.code}): {e.read().decode()[:300]}")
    print(f"queued {pid} (seed {a.seed}); rendering...", file=sys.stderr)
    while True:
        time.sleep(3)
        h = json.loads(request(f"{a.comfy}/history/{pid}"))
        if pid not in h:
            continue
        status = h[pid]["status"]
        if status.get("status_str") != "success":
            sys.exit("failed: " + json.dumps(status.get("messages", []))[-800:])
        f = next(f for o in h[pid]["outputs"].values() for f in o.get("images", []) + o.get("videos", []))
        q = urllib.parse.urlencode({"filename": f["filename"], "subfolder": f.get("subfolder", ""), "type": f.get("type", "output")})
        open(a.out, "wb").write(request(f"{a.comfy}/view?{q}", timeout=300))
        print(f"{a.out} ({time.time() - t:.0f}s)", file=sys.stderr)
        return


if __name__ == "__main__":
    main()

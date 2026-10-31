"""Fetch pinned CPU inference framework and multilingual weights for an offline IPA."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request


def fetch(url, target, checksum=None):
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=180) as response:
        data = response.read()
    if checksum and hashlib.sha256(data).hexdigest() != checksum:
        raise RuntimeError(f"Checksum mismatch: {target}")
    target.write_bytes(data)
    print(f"{target}: {len(data)} bytes", flush=True)


fetch("https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin",
      "VoiceModels/ggml-base.bin", "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe")
fetch("https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.2/whisper-v1.8.2-xcframework.zip",
      "build/whisper-framework.zip", "3ffeec1df254d908f01ee3d87bf0aedb8fbc8f29cbf50dc8702741bb85381385")
subprocess.run(["unzip", "-q", "build/whisper-framework.zip", "-d", "build/whisper-framework"], check=True)
shutil.copytree("build/whisper-framework/build-apple/whisper.xcframework",
                "Vendor/WhisperBinary/whisper.xcframework", symlinks=True, dirs_exist_ok=True)
fetch("https://raw.githubusercontent.com/openai/whisper/main/LICENSE", "VoiceModels/Whisper-LICENSE.txt")
fetch("https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.8.2/LICENSE", "VoiceModels/WhisperCpp-LICENSE.txt")

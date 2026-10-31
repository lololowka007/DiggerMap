"""Bundle a pinned multilingual Whisper model and tokenizer for fully local use."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path("VoiceModels")
REPO = "argmaxinc/whisperkit-coreml"
REV = "0f63a7800b00dd0226abd051b906c246e1907482"
MODEL = "openai_whisper-base"
TOK_REV = "e37978b90ca9030d5170a5c07aadb050351a65bb"


def fetch(url, target, digest=None):
    target.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=180) as response:
        data = response.read()
    if digest and hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError(f"Model checksum mismatch: {target}")
    target.write_bytes(data)
    print(f"{target}: {len(data)} bytes", flush=True)


url = f"https://huggingface.co/api/models/{REPO}/tree/{REV}/{MODEL}?recursive=true&limit=100"
with urllib.request.urlopen(url) as response:
    files = json.load(response)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    futures = [
        pool.submit(fetch, f"https://huggingface.co/{REPO}/resolve/{REV}/{item['path']}",
                    ROOT / item["path"], item.get("lfs", {}).get("oid"))
        for item in files if item["type"] == "file"
    ]
    for future in futures:
        future.result()
for name in ("tokenizer.json", "tokenizer_config.json", "config.json", "special_tokens_map.json"):
    fetch(f"https://huggingface.co/openai/whisper-base/resolve/{TOK_REV}/{name}",
          ROOT / "Tokenizers/models/openai/whisper-base" / name)
fetch("https://raw.githubusercontent.com/openai/whisper/main/LICENSE", ROOT / "Whisper-LICENSE.txt")
fetch("https://raw.githubusercontent.com/argmaxinc/WhisperKit/v0.9.4/LICENSE", ROOT / "WhisperKit-LICENSE.txt")

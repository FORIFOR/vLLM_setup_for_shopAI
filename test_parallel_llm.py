"""8並列の疎通・負荷テスト（標準ライブラリのみ、依存インストール不要）。
GPU PC 自身でもBackend VMからでも実行可。トークンは同ディレクトリの .env から自動読込。

実行例:
    python3 test_parallel_llm.py
    VLLM_URL=http://192.168.0.15:8000/v1/chat/completions python3 test_parallel_llm.py
"""
import json
import os
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def load_token() -> str:
    tok = os.environ.get("VLLM_API_KEY")
    if tok:
        return tok
    env_path = Path(__file__).resolve().parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("VLLM_API_KEY"):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("VLLM_API_KEY が見つかりません (.env か環境変数で指定してください)")


URL = os.environ.get("VLLM_URL", "http://127.0.0.1:8000/v1/chat/completions")
TOKEN = load_token()
N = int(os.environ.get("VLLM_N", "8"))


def ask(i: int) -> tuple[int, float, int, str]:
    body = json.dumps({
        "model": "shopai-fast",
        "messages": [
            {"role": "system", "content": "あなたは店舗案内スタッフです。2文以内で答えてください。/no_think"},
            {"role": "user", "content": f"来店者{i}に営業時間の確認方法を案内してください。"},
        ],
        "temperature": 0.2,
        "max_tokens": 96,
    }).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=body,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            status = resp.status
            payload = json.loads(resp.read().decode("utf-8"))
        content = payload["choices"][0]["message"]["content"]
        # Qwen3 の空 <think>...</think> 接頭辞を除去して表示
        if "</think>" in content:
            content = content.split("</think>", 1)[1].strip()
    except urllib.error.HTTPError as e:
        status, content = e.code, f"<HTTPError: {e.read()[:120]!r}>"
    except Exception as e:  # noqa: BLE001
        status, content = 0, f"<error: {e}>"
    return i, time.perf_counter() - started, status, content


def main() -> None:
    started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=N) as pool:
        results = list(pool.map(ask, range(N)))
    total = time.perf_counter() - started

    ok = 0
    for i, elapsed, status, text in sorted(results):
        good = status == 200 and bool(text.strip())
        ok += good
        flag = "OK " if good else "NG "
        print(f"{flag}{i}: {elapsed:5.2f}s [{status}] | {text[:60].replace(chr(10), ' ')}")
    print(f"---\nTOTAL: {total:.2f}s | 200&非空: {ok}/{N}")


if __name__ == "__main__":
    main()

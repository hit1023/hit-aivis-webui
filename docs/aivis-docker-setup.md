# AivisSpeech Engine — Docker セットアップ手順

> 対象環境: Ubuntu / NVIDIA GPU 搭載サーバー  
> ポート構成: 10101 / 10102 / 10103 の 3 インスタンス

---

## 1. 前提条件

| 項目 | 確認コマンド |
|---|---|
| Docker / Docker Compose | `docker compose version` |
| NVIDIA Container Toolkit | `nvidia-smi` |

NVIDIA Container Toolkit が未インストールの場合:

```bash
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list \
  | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo systemctl restart docker
```

---

## 2. 既存コンテナの停止

```bash
# Docker コンテナ
docker stop tts_inference_service_01 tts_inference_service_02 tts_inference_service_03

# LXD コンテナ（存在する場合）
lxc stop aivis
lxc stop aivis2
lxc stop gpu-1
```

停止確認:

```bash
docker ps | grep tts_inference
lxc list
```

---

## 3. 作業ディレクトリの作成

```bash
mkdir -p ~/workspaces/hit/tts
cd ~/workspaces/hit/tts
```

---

## 4. docker-compose.yml の作成

```yaml
services:
  aivis-01:
    image: ghcr.io/aivis-project/aivisspeech-engine:nvidia-latest
    container_name: aivis_01
    ports:
      - "10101:10101"
    volumes:
      - ./data:/home/user/.local/share/AivisSpeech-Engine-Dev
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped

  aivis-02:
    image: ghcr.io/aivis-project/aivisspeech-engine:nvidia-latest
    container_name: aivis_02
    ports:
      - "10102:10101"
    volumes:
      - ./data:/home/user/.local/share/AivisSpeech-Engine-Dev
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped

  aivis-03:
    image: ghcr.io/aivis-project/aivisspeech-engine:nvidia-latest
    container_name: aivis_03
    ports:
      - "10103:10101"
    volumes:
      - ./data:/home/user/.local/share/AivisSpeech-Engine-Dev
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped
```

> **ポイント**: 3 インスタンスで `./data` を共有するため、モデルのインストールは 1 回で全インスタンスに反映されます。

---

## 5. データディレクトリの権限設定

```bash
mkdir -p data
sudo chown -R 1000:1000 data
```

---

## 6. 起動

```bash
docker compose pull
docker compose up -d
```

---

## 7. 動作確認

```bash
# コンテナ起動確認
docker compose ps

# バージョン確認（各インスタンス）
curl -s http://localhost:10101/version
curl -s http://localhost:10102/version
curl -s http://localhost:10103/version

# GPU 使用確認
nvidia-smi
```

正常起動時、nvidia-smi に 3 プロセスがそれぞれ約 882MiB の VRAM を確保して表示されます。

---

## 8. run.sh（管理スクリプト）の作成

`run.sh` を作成して以下を貼り付け、`chmod +x run.sh` で実行権限を付与:

```bash
#!/bin/bash

COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/docker-compose.yml"
INSTANCES=("aivis_01:10101" "aivis_02:10102" "aivis_03:10103")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║       AivisSpeech Engine Manager         ║"
  echo "  ╚══════════════════════════════════════════╝"
  echo -e "${RESET}"
}

show_status() {
  echo -e "${BOLD}── インスタンス状態 ──────────────────────────${RESET}"
  for entry in "${INSTANCES[@]}"; do
    IFS=':' read -r name port <<< "$entry"
    running=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo "false")
    if [ "$running" = "true" ]; then
      version=$(curl -s --max-time 2 "http://localhost:${port}/version" 2>/dev/null || echo "---")
      mem=$(docker stats --no-stream --format "{{.MemUsage}}" "$name" 2>/dev/null || echo "---")
      echo -e "  ${GREEN}●${RESET} ${BOLD}${name}${RESET} ${DIM}:${port}${RESET}  ver=${CYAN}${version}${RESET}  mem=${mem}"
    else
      echo -e "  ${RED}●${RESET} ${BOLD}${name}${RESET} ${DIM}:${port}${RESET}  ${RED}停止中${RESET}"
    fi
  done
  echo ""
  echo -e "${BOLD}── GPU 状態 ───────────────────────────────────${RESET}"
  nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total \
    --format=csv,noheader,nounits 2>/dev/null | \
  awk -F', ' '{printf "  %s  |  %s°C  |  Util: %s%%  |  VRAM: %s/%s MiB\n", $1,$2,$3,$4,$5}' \
  || echo -e "  ${YELLOW}nvidia-smi が見つかりません${RESET}"
  echo ""
}

show_menu() {
  echo -e "${BOLD}── メニュー ───────────────────────────────────${RESET}"
  echo -e "  ${CYAN}1${RESET}) 全台 起動"
  echo -e "  ${CYAN}2${RESET}) 全台 停止"
  echo -e "  ${CYAN}3${RESET}) 全台 再起動"
  echo -e "  ${DIM}  ────────────────────────────${RESET}"
  echo -e "  ${CYAN}4${RESET}) インスタンス01 起動/停止"
  echo -e "  ${CYAN}5${RESET}) インスタンス02 起動/停止"
  echo -e "  ${CYAN}6${RESET}) インスタンス03 起動/停止"
  echo -e "  ${DIM}  ────────────────────────────${RESET}"
  echo -e "  ${CYAN}7${RESET}) ログ（全体）"
  echo -e "  ${CYAN}8${RESET}) ログ（01）  ${CYAN}9${RESET}) ログ（02）  ${CYAN}a${RESET}) ログ（03）"
  echo -e "  ${DIM}  ────────────────────────────${RESET}"
  echo -e "  ${CYAN}m${RESET}) モデル一覧"
  echo -e "  ${CYAN}u${RESET}) 最新イメージを取得"
  echo -e "  ${CYAN}0${RESET}) 終了"
  echo ""
  echo -ne "${BOLD}選択 > ${RESET}"
}

toggle_instance() {
  local name=$1
  running=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo "false")
  if [ "$running" = "true" ]; then
    echo -e "${BOLD}${name} を停止中...${RESET}"
    docker stop "$name"
    echo -e "${GREEN}停止しました${RESET}"
  else
    echo -e "${BOLD}${name} を起動中...${RESET}"
    docker start "$name"
    echo -e "${GREEN}起動しました${RESET}"
  fi
  sleep 2
}

cmd_models() {
  echo -e "${BOLD}── インストール済みモデル ────────────────────${RESET}"
  for entry in "${INSTANCES[@]}"; do
    IFS=':' read -r name port <<< "$entry"
    running=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo "false")
    if [ "$running" = "true" ]; then
      echo -e "\n  ${CYAN}${name}${RESET} (:${port})"
      curl -s "http://localhost:${port}/aivm_models" 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data:
    print('    (モデルなし)')
for uuid, info in data.items():
    n = info.get('manifest', {}).get('name', uuid)
    loaded = '✓ VRAM' if info.get('is_loaded') else '  disk'
    print(f'    [{loaded}] {n}')
" 2>/dev/null || echo "    取得失敗"
    fi
  done
  echo ""
  echo -e "${DIM}Enterで戻る...${RESET}"; read -r
}

while true; do
  banner
  show_status
  show_menu
  read -r choice

  case "$choice" in
    1) banner; echo -e "${BOLD}全台起動中...${RESET}"; docker compose -f "$COMPOSE_FILE" up -d; sleep 3 ;;
    2) banner; echo -e "${BOLD}全台停止中...${RESET}"; docker compose -f "$COMPOSE_FILE" stop; echo -e "${GREEN}停止しました${RESET}"; sleep 2 ;;
    3) banner; echo -e "${BOLD}全台再起動中...${RESET}"; docker compose -f "$COMPOSE_FILE" restart; sleep 3 ;;
    4) banner; toggle_instance aivis_01 ;;
    5) banner; toggle_instance aivis_02 ;;
    6) banner; toggle_instance aivis_03 ;;
    7) docker compose -f "$COMPOSE_FILE" logs -f --tail=50 ;;
    8) docker logs -f aivis_01 --tail=50 ;;
    9) docker logs -f aivis_02 --tail=50 ;;
    a) docker logs -f aivis_03 --tail=50 ;;
    m) banner; cmd_models ;;
    u) banner; echo -e "${BOLD}最新イメージを取得中...${RESET}"; docker compose -f "$COMPOSE_FILE" pull; echo -e "${GREEN}完了${RESET}"; sleep 2 ;;
    0) echo -e "${DIM}終了します${RESET}"; exit 0 ;;
    *) echo -e "${YELLOW}無効な選択です${RESET}"; sleep 1 ;;
  esac
done
```

---

## 9. ディレクトリ構成

```
~/workspaces/hit/tts/
├── docker-compose.yml
├── run.sh
└── data/                  ← 3インスタンス共有
    └── Models/            ← .aivmx モデルファイル
```

---

## 10. トラブルシューティング

**audio_query が 500 エラー**  
AivisSpeech サーバー自体の問題の可能性が高いです。コンテナを再起動してください:

```bash
docker compose restart
```

**ログに `/mumon_models/running` の 404 が大量に出る**  
旧カスタムイメージ向けのエンドポイントを古いサービスがポーリングしています。動作には影響ありません。

---

*AivisSpeech Engine — https://github.com/Aivis-Project/AivisSpeech-Engine*

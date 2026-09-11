#!/bin/bash

# ===================== 自定义配置区 =====================
UUID="0007ff14-4fa3-4d3b-ab22-168c8676aff3"
DOMAIN=""        # cf解析的域名
WS_PATH="/w33d3j3uu23ysh38e29"   # WebSocket 路径
SERVER_ADDR=""     # 优选ip或域名，留空则设为www.visa.com，端口443

# ========================================================
# 内存监控阈值 (单位: MB)
MEM_THRESHOLD=48

PORT=${SERVER_PORT:-8080} 
FINAL_ADDR=${SERVER_ADDR:-"www.visa.com"}
WORK_DIR="proxy_files"
mkdir -p "$WORK_DIR"
SB_BIN="$WORK_DIR/sing-box"
SB_CONFIG="$WORK_DIR/config.json"
NODE_FILE="node.txt"

# 1. 下载 sing-box (AMD64 架构)
if [[ ! -x "$SB_BIN" ]]; then
    URL="https://github.com/oxdtotest/cdn.sh/releases/download/v1.12.17/sing-box-1.12.17-linux-amd64"
    curl -L -f -o "$SB_BIN" "$URL"
    chmod +x "$SB_BIN"
fi

# 2. 生成配置
cat > "$SB_CONFIG" <<EOF
{
  "log": { "disabled": true, "level": "panic" },
  "inbounds": [{
    "type": "vless",
    "tag": "vless-ws-in",
    "listen": "::",
    "listen_port": $PORT,
    "users": [{ "uuid": "$UUID" }],
    "transport": { "type": "ws", "path": "$WS_PATH" }
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF

# 3. 生成并保存节点链接
VLESS_LINK="vless://$UUID@$FINAL_ADDR:443?encryption=none&security=tls&sni=$DOMAIN&type=ws&path=$WS_PATH#VLESS-cdn"

# 将链接写入 node.txt
echo "$VLESS_LINK" > "$NODE_FILE"

echo "---------------------------------------------------"
echo "🚀 sing-box运行中"
echo "节点链接已保存至: $NODE_FILE"
echo "---------------------------------------------------"
echo "🔗 节点链接:"
echo "$VLESS_LINK"
echo "---------------------------------------------------"

# 4. 内存监控守护函数 (低内存环境优化)
monitor_mem() {
    hit_count=0
    while true; do
        sleep 60
        pid=$(pgrep -f "$SB_BIN")
        if [ -z "$pid" ]; then continue; fi
        
        mem_usage=$(ps -o rss= -p "$pid" | awk '{print int($1/1024)}')
        
        if [ "$mem_usage" -gt "$MEM_THRESHOLD" ]; then
            ((hit_count++))
            if [ "$hit_count" -ge 3 ]; then
                kill -9 "$pid"
                hit_count=0
            fi
        else
            hit_count=0
        fi
    done
}

# 5. 性能限制与进程拉起
export GOGC=20
export GOMEMLIMIT=35MiB
export GOMAXPROCS=1

monitor_mem & 

while true; do
    "$SB_BIN" run -c "$SB_CONFIG" &
    child_pid=$!
    wait $child_pid
    sleep 3
done

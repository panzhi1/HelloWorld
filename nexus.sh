#!/bin/bash

# 定义服务名称和文件路径
SERVICE_NAME="nexus"
SERVICE_FILE="/etc/systemd/system/nexus.service"

# 脚本保存路径
SCRIPT_PATH="$HOME/nexus/"

# 启动节点并保存 Prover ID 的函数
function start_and_save_id() {
    # 启动节点
    start_node

    # 获取 Prover ID
    local max_retries=100
    local retry_count=0
    prover_id=""

    while [ -z "$prover_id" ] && [ $retry_count -lt $max_retries ]; do
        prover_id=$(cat /root/.nexus/prover-id)
        if [ -z "$prover_id" ]; then
            echo "未能获取到 Prover ID,正在重试..."
            retry_count=$((retry_count + 1))
            sleep 5
        fi
    done

    if [ -z "$prover_id" ]; then
        echo "无法获取 Prover ID,脚本终止。"
        exit 1
    fi


   # 将 Prover ID 保存到文件
   PROVER_ID_FILE="/root/nexus/prover-ids.txt"
   echo "$prover_id" >> "$PROVER_ID_FILE"

   echo "Prover ID 已保存到 $PROVER_ID_FILE 文件中。"

}

# 启动节点的函数
function start_node() {
    # 检查服务是否正在运行
    if systemctl is-active --quiet nexus.service; then
        echo "nexus.service 当前正在运行。正在停止并禁用它..."
        sudo systemctl stop nexus.service
        sudo systemctl disable nexus.service
    else
        echo "nexus.service 当前未运行。"
    fi

    # 确保目录存在
    mkdir -p /root/.nexus

    # 更新系统并安装必要的软件包
    echo "更新系统并安装必要的软件包..."
    if ! sudo apt update && sudo apt upgrade -y && sudo apt install curl iptables git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip -y; then
        echo "安装软件包失败。"
        exit 1
    fi

    # 单独安装 build-essential
    if ! sudo apt install build-essential -y; then
        echo "安装 build-essential 失败。"
        exit 1
    fi

    # 检查并安装 Git
    if ! command -v git &> /dev/null; then
        echo "Git 未安装。正在安装 Git..."
        if ! sudo apt install git -y; then
            echo "安装 Git 失败。"
            exit 1
        fi
    else
        echo "Git 已安装。"
    fi

    # 检查 Rust 是否已安装
    if command -v rustc &> /dev/null; then
        echo "Rust 已安装，版本为: $(rustc --version)"
    else
        echo "Rust 未安装，正在安装 Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        echo "Rust 安装完成。"
        source $HOME/.cargo/env
        export PATH="$HOME/.cargo/bin:$PATH"
        echo "Rust 环境已加载。"
    fi

    if [ -d "$HOME/network-api" ]; then
        show "正在删除现有的仓库..." "progress"
        rm -rf "$HOME/network-api"
    fi

    # 克隆指定的 GitHub 仓库
    echo "正在克隆仓库..."
    cd
    git clone https://github.com/nexus-xyz/network-api.git

    # 安装依赖项
    cd $HOME/network-api/clients/cli
    echo "安装所需的依赖项..."
    if ! sudo apt install pkg-config libssl-dev -y; then
        echo "安装依赖项失败。"
        exit 1
    fi

    # 创建 systemd 服务文件
    echo "创建 systemd 服务..."
    if ! sudo bash -c "cat > $SERVICE_FILE <<EOF
[Unit]
Description=Nexus XYZ Prover Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/network-api/clients/cli
Environment=NONINTERACTIVE=1
Environment=PATH=/root/.cargo/bin:$PATH
ExecStart=$HOME/.cargo/bin/cargo run --release --bin prover -- beta.orchestrator.nexus.xyz
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"; then
        echo "创建 systemd 服务文件失败。"
        exit 1
    fi

    # 重新加载 systemd 并启动服务
    echo "重新加载 systemd 并启动服务..."
    if ! sudo systemctl daemon-reload; then
        echo "重新加载 systemd 失败。"
        exit 1
    fi

    if ! sudo systemctl start nexus.service; then
        echo "启动服务失败。"
        exit 1
    fi

    if ! sudo systemctl enable nexus.service; then
        echo "启用服务失败。"
        exit 1
    fi

    echo "节点启动成功!"
}

# 删除节点的函数
function delete_node() {
    echo "正在删除节点..."
    sudo systemctl stop nexus.service
    sudo systemctl disable nexus.service
    rm -rf /root/network-api
    rm -rf /etc/systemd/system/nexus.service
    rm -f /root/.nexus/prover-id
    echo "成功删除节点。"
}

# 主程序
echo "开始自动启动和删除节点,并保存 Prover ID..."

# 创建 Prover ID 保存文件
touch /root/.nexus/prover-ids.txt

# 重复 10 次启动、保存 ID、删除、重启的过程
for i in {1..30}; do
    echo "第 $i 次迭代..."
    start_and_save_id
    # 延迟 1 分钟后删除节点
    echo "正在等待 5 分钟后删除节点..."
    sleep 300
    delete_node
    sleep 30
done

echo "所有操作完成。Prover ID 已保存到 /root/.nexus/prover-ids.txt 文件中。"
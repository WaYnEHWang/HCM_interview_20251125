# 第二題：Docker Log 蒐集 – 規劃方案、建置手冊與執行說明

題目要求我們處理兩種情境：

1. **實體檔案形式的log**  
   - 應用程式把log寫到檔案（例如 `app.log`）
2. **透過 `docker logs` 指令輸出的 log**  
   - 應用程式只把log印在畫面上（stdout/stderr）

這份文件會依序提供：

- **規劃方案**：說明清楚整體架構  
- **建置手冊**：說明操作流程  
- **執行與驗證說明**：怎麼確認log是否送到CloudWatch

## 1. 整體架構與前置假設

### 1.1 環境假設
為了讓文件簡單、具體，我們先假設：
- 雲端環境：AWS
- 區域（Region）：`ap-northeast-1`（東京）
- 有一台 EC2 主機：
  - 作業系統：**Amazon Linux 2023**
  - 已安裝 Docker（下面會補簡單安裝步驟）
  - 這台主機上跑著你的 Docker 容器
- EC2 有掛一個 IAM Role，權限包含：
  - `logs:CreateLogGroup`
  - `logs:CreateLogStream`
  - `logs:PutLogEvents`
  - `logs:DescribeLogGroups`
  - `logs:DescribeLogStreams`

可以沿用第一題建立好的：
- CloudWatch Log Group 命名規則（例如 `/docker/dev/hcm-api`）
- IAM Role（例如 `docker-logs-role-dev-hcm-api`），如果無法使用可以自行建立可掛載到EC2的IAM role，權限可以直接使用CloudWatchLogsFullAccess政策以方便測試。

### 1.2 你需要準備的帳號與工具
讀這份文件的人需要具備：
1. 一個可以登入 AWS Console 的帳號  
2. 對那個帳號所屬AWS環境有足夠權限去：
   - 建 EC2
   - 建 / 修改 IAM Role
   - 看 CloudWatch Logs
3. 能透過SSH登入EC2（例如有`.pem`金鑰檔）

### 1.3 簡短：如何 SSH 進 EC2（參考）
假設你已經：
- 下載好金鑰，例如：`my-ec2-key.pem`
- EC2 的 Public IP：`3.113.123.45`
- 系統為 Amazon Linux → 預設帳號是 `ec2-user`

在 Mac / Linux 的 Terminal：
在金鑰的存放位址輸入以下指令。
```bash
chmod 400 my-ec2-key.pem
ssh -i my-ec2-key.pem ec2-user@3.113.123.45
```
連進去之後，你會看到類似：
```bash
[ec2-user@ip-10-0-0-123 ~]$
```
代表已經成功登入那台主機。

## 2. 前置準備 – 安裝 Docker（如果尚未安裝）
如果你的EC2已經可以執行 docker ps 指令並顯示空列表，就可以略過這一小節。

在Amazon Linux 2023上安裝Docker：
```bash
# 更新套件
sudo yum update -y

# 安裝 Docker
sudo yum install -y docker

# 啟動 Docker 服務並設為開機自動啟動
sudo systemctl start docker
sudo systemctl enable docker

# 讓 ec2-user 可以直接下 docker 指令（登出再登入一次才會生效）
sudo usermod -aG docker ec2-user
```

重新登入SSH後，用下列指令確認：
```bash
docker ps
```
若沒錯誤，且顯示「空列表」，代表 Docker 已安裝成功，且目前沒有容器在跑。


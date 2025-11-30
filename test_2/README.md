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
  - 這台主機上跑著你的Docker容器
- EC2 有掛一個IAM Role，權限包含：
  - `logs:CreateLogGroup`
  - `logs:CreateLogStream`
  - `logs:PutLogEvents`
  - `logs:DescribeLogGroups`
  - `logs:DescribeLogStreams`

可以沿用第一題建立好的：
- CloudWatch Log Group 命名規則（例如 `/docker/dev/hcm-api`）
- IAM Role（例如 `docker-logs-role-dev-hcm-api`），如果無法使用可以自行建立可掛載到EC2的IAM role，權限可以直接使用`CloudWatchLogsFullAccess`政策以方便測試。

### 1.2 你需要準備的帳號與工具
讀這份文件的人需要具備：
1. 一個可以登入 AWS Console 的帳號  
2. 對那個帳號所屬AWS環境有足夠權限去：
   - 建EC2
   - 建立/修改IAM Role
   - 看CloudWatch Logs
3. 能透過SSH登入EC2（例如有`.pem`金鑰檔）

### 1.3 如何SSH進EC2
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

## 3. 情境一：實體檔案形式的log

### 3.1 規劃方案
這一種情況是：
- 你容器裡的程式，會把 log 寫到檔案，例如`/var/log/app/app.log` 

我們要做的是：

1. 用Docker Volume，把容器內的`/var/log/app`掛到主機的`/var/log/myapp`，這樣主機就看得到實體log檔
2. 在這台主機安裝CloudWatch Agent
3. 告訴CloudWatch Agent：「監視`/var/log/myapp/app.log`，有新log就送去特定的CloudWatch Log Group」

「架構圖」大概是這樣：
```bash
[App in Container] --寫檔--> /var/log/app/app.log
         | (Volume 掛載)
         V
[EC2 Host] /var/log/myapp/app.log --CloudWatch Agent--> [CloudWatch Log Group]
```

### 3.2 建置手冊：實體log檔案方案
步驟 1：在主機建立log目錄
登入EC2後：
```bash
sudo mkdir -p /var/log/myapp
sudo chown ec2-user:ec2-user /var/log/myapp
```
這是主機的log目錄，我們會把容器log掛出來到這裡。

步驟 2：啟動一個會寫檔案log的容器

這裡先用一個簡單的測試容器代替：
```bash
docker run -d --name file-logger \
  -v /var/log/myapp:/var/log/app \
  alpine /bin/sh -c "while true; do date >> /var/log/app/app.log; echo 'ERROR something bad' >> /var/log/app/app.log; sleep 10; done"
```

說明：
- `-v /var/log/myapp:/var/log/app`把主機的`/var/log/myapp`掛到容器內的`/var/log/app`
- 容器內的腳本每 10 秒會寫一行時間與一行「ERROR something bad」到`app.log`

在主機上可以確認檔案是否真的在寫：
```bash
tail -f /var/log/myapp/app.log
```
如果每 10 秒看到新的內容，代表這一層沒問題。

步驟 3：安裝CloudWatch Agent

在 Amazon Linux 2023 上：
```bash
sudo yum install -y amazon-cloudwatch-agent
```

安裝成功後，主要會用到：

- 執行控制：`/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl`
- 設定檔位置（可自訂）：我們用`/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`

步驟 4：建立CloudWatch Agent設定檔

在 EC2 上建立設定檔：
```bash
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null << 'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/myapp/app.log",
            "log_group_name": "/docker/dev/myapp-file",
            "log_stream_name": "{hostname}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  }
}
EOF
```
說明：
- `file_path`：主機上的log檔路徑（Volume 掛出來的那個）
- `log_group_name`：CloudWatch Log Group名稱，你可以依環境命名，例如：
  - `/docker/dev/myapp-file`
  - `/docker/uat/myapp-file`等
- `log_stream_name`：`{hostname}`代表自動使用主機名做stream名稱
- `timestamp_format`：依你log裡時間格式調整；若log沒時間戳，CloudWatch會用收訊時間

步驟 5：啟動CloudWatch Agent

執行：
```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
```
- `-a fetch-config`：使用指定的設定檔
- `-m ec2`：告訴 agent 自己跑在 EC2 上
- `-s`：啟動服務
檢查服務狀態：
```bash
sudo systemctl status amazon-cloudwatch-agent
```
看到`active (running)`就代表agent正在運作。

3.3 執行與驗證：檔案log方案

1. 確認測試容器還在跑：
```bash
docker ps
```
應該可以看到一個叫`file-logger`的容器。

2. 到AWS Console → CloudWatch → Log groups：
- 找`log_group_name`設定裡的名稱，例如：`/docker/dev/myapp-file`
- 點進去 → 會看到一個或多個Log Stream（名稱為主機名）

3. 點進某個Log Stream，檢查log內容：
- 應該可以看到類似：
```bash
Mon Jan  1 00:00:00 UTC 2025
ERROR something bad
...
```
如果有，就代表：Docker → 寫log到檔案 → Volume掛到主機 → CloudWatch Agent送到 CloudWatch」已經成功。

## 4. 情境二：透過docker logs輸出的log（stdout / stderr）
這一種情況是：

- 應用程式不寫檔案，只把log印到畫面（stdout/stderr）
- 平常我們會用：
```bash
docker logs <container-name>
```
來查看 log。

這時我們不用上一個情境的方式，而是改用：

Docker內建的logging driver：`awslogs`

讓Docker直接把stdout/stderr寫進CloudWatch Logs。

4.1 規劃方案

架構：
```bash
[App in Container] --印log到stdout/stderr-->
[Docker Engine] --awslogs logging driver--> [CloudWatch Log Group]
```

4.2 建置手冊：stdout log 方案
步驟 1：確認EC2有CloudWatch Logs權限的IAM Role

一樣需要：

- EC2掛載的IAM Role具備log權限
- 請確認 Role 是否至少有：
  - logs:CreateLogGroup
  - logs:CreateLogStream
  - logs:PutLogEvents

步驟 2：啟動一個使用awslogs logging driver的容器（測試）

在 EC2 上執行：
```bash
docker run --rm \
  --name myapp-stdout-test \
  --log-driver=awslogs \
  --log-opt awslogs-region=ap-northeast-1 \
  --log-opt awslogs-group=/docker/dev/myapp-stdout \
  --log-opt awslogs-stream=myapp-stdout-test \
  alpine /bin/sh -c "echo 'INFO hello from docker'; echo 'ERROR something happened'; sleep 5"
```
說明：

- `--log-driver=awslogs`告訴Docker：把這個容器的stdout/stderr丟到 CloudWatch Logs。
- `awslogs-region`：AWS區域（這裡用ap-northeast-1）
- `awslogs-group`：CloudWatch Log Group名稱（沒有的話會被自動建立）
- `awslogs-stream`：此容器對應的log stream名稱
- `alpine ...` 那段指令只是做一個測試：
  - 印一行 INFO
  - 印一行 ERROR
  - 等 5 秒後結束

若你想讓它持續輸出 log，可以改成：
```bash
docker run -d \
  --name myapp-stdout-test \
  --log-driver=awslogs \
  --log-opt awslogs-region=ap-northeast-1 \
  --log-opt awslogs-group=/docker/dev/myapp-stdout \
  --log-opt awslogs-stream=myapp-stdout-test \
  alpine /bin/sh -c "while true; do echo 'ERROR from loop'; sleep 10; done"
  ```

4.3 執行與驗證：stdout log方案

1. 在EC2上查看容器log（確保stdout正常）：
```bash
docker logs -f myapp-stdout-test
```
應該會看到類似：
```bash
INFO hello from docker
ERROR something happened
```

2. 到AWS Console → CloudWatch → Log groups：
  - 找名稱 `/docker/dev/myapp-stdout`
  - 點進去，看 Log Stream `myapp-stdout-test`

3. 在Log Stream內查看log內容：
  - 應該會看到你在容器裡`echo`出來的那些文字

如果有，就代表：Docker stdout/stderr → Docker awslogs driver → CloudWatch Logs 已經成功了。

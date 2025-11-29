# Docker Logs → CloudWatch 監控架構（Terraform + Terragrunt）

本專案使用 **Terraform + Terragrunt** 在 AWS 上建立一套用來監控 Docker 容器 log 的架構，包含：

- **CloudWatch Logs Log Group**：集中收集 Docker 容器 log  
- **CloudWatch Metric Filter & Alarm**：偵測 log 中的 `ERROR`，並發送告警  
- **SNS Topic + Email Subscription**：告警時寄信通知  
- **CloudWatch Dashboard**：可視化 ErrorCount 與最近 ERROR logs  
- **IAM Role & Policy**：給 EC2（Docker Host）使用，把 log 寫入 CloudWatch Logs  
- **Terraform Remote State**：使用 S3 + DynamoDB 管理 IaC 狀態  

此文件說明：

1. 專案目錄與結構說明  
2. 部署前置需求（工具、權限、AWS 設定）  
3. 建立S3 Bucket 與DynamoDB Table（Terraform backend）
4. 需要修改的檔案與參數  
5. 如何驗證SNS郵件  
6. 如何在本機執行部署

---

## 1. 專案目錄結構

```text
project
└─ terraform
   ├─ live
   │  ├─ root.hcl                 # 共用 remote_state & provider 設定
   │  ├─ dev
   │  │  ├─ env.hcl               # dev 環境變數（email、retention）
   │  │  └─ docker-logs
   │  │     └─ terragrunt.hcl     # dev 環境 docker logs 部署設定
   │  ├─ uat
   │  │  ├─ env.hcl
   │  │  └─ docker-logs
   │  │     └─ terragrunt.hcl
   │  └─ prod
   │     ├─ env.hcl
   │     └─ docker-logs
   │        └─ terragrunt.hcl
   └─ modules
      └─ docker-logs
         ├─ main.tf               # 主要資源（LogGroup / Alarm / Dashboard / IAM / SNS）
         ├─ outputs.tf
         ├─ variables.tf
         └─ versions.tf
```


## 2. 部署前置需求（工具、權限、AWS 設定）


2.1 必要工具

請先在本機安裝：
- **Terraform（建議版本 ≥ 1.3.0）**
- **Terragrunt**
- **AWS CLI**

安裝完成後，確認指令可用：
```text
terraform -version
terragrunt --version
aws --version
```
2.2 AWS 憑證與權限

執行 IaC 的 AWS 身分（IAM User 或 Role）需要具備權限：
- **S3：建立 / 讀寫 bucket & objects**
- **DynamoDB：建立 / 讀寫 table（做 lock 用）**
- **IAM：建立 Role / Policy / Policy Attachment**
- **CloudWatch Logs / Metrics / Alarms / Dashboard**
- **SNS：建立 Topic / Subscription**

在本機設定 AWS CLI 憑證：
```text
aws configure
```
# 輸入 Access Key ID
# 輸入 Secret Access Key
# Default region name: 建議ap-northeast-1
# Default output format: 可留空或輸入json

## 3. 建立 S3 Bucket 與 DynamoDB Table（Terraform backend）

Terraform 使用 remote backend，需要一個 S3 bucket + DynamoDB table 來存放與鎖定 state。

預設名稱可改，但須與程式碼一致，若你修改名稱，請在terraform/live/root.hcl 裡一起更新）：
S3 Bucket：weihan-tf-state-bucket
DynamoDB Table：weihan-tf-lock-table
Region：ap-northeast-1（東京）


3.1 建立 S3 Bucket

登入 AWS Console → 搜尋 S3
點 Create bucket
設定：
- **Bucket name：weihan-tf-state-bucket**
- **AWS Region：ap-northeast-1**

建議設定：
勾選：Block all public access
可開啟 Bucket versioning（方便日後回滾 state）
按 Create bucket

3.2 建立 DynamoDB Table

在 AWS Console 搜尋並開啟 DynamoDB
點 Create table

設定：
- **Table name：weihan-tf-lock-table**
- **Partition key：LockID，型別 String**
其他設定維持預設，按 Create table
此 Table 用於 Terraform 的 state locking，避免多人同時 apply 導致 state 損壞。

## 4. 需要修改的檔案與參數

4.1 terraform/live/root.hcl

設定 remote_state 與共用 provider： remote_state.config.bucket/region/dynamodb_table 可換成自己偏好的名稱跟地區

4.2 各環境 env.hcl
dev 環境：terraform/live/dev/env.hcl
uat 環境：terraform/live/uat/env.hcl
prod 環境：terraform/live/prod/env.hcl

locals.alarm_email: 換成要接收告警的郵件
locals.log_retention_days: 設定Log保留天數（天）

4.3 各環境 docker-logs/terragrunt.hcl
dev 環境：terraform/live/dev/docker-logs/terragrunt.hcl
uat 環境：terraform/live/uat/docker-logs/terragrunt.hcl
prod 環境：terraform/live/prod/docker-logs/terragrunt.hcl

inputs.service_name: 要監控的 Docker 服務名稱

4.4 Module terraform/modules/docker-logs/versions.tf
terraform.required_version: 可以設定版本


## 5. 如何驗證SNS郵件

Terraform 會建立：
    SNS Topic：aws_sns_topic.alarm_topic
    SNS Subscription：aws_sns_topic_subscription.alarm_email
建立後，SNS 會自動寄出一封 Subscription Confirmation 郵件到 env.hcl 裡設定的 alarm_email。

驗證步驟
1. 到設定的 email 信箱收信(有可能在垃圾信件)
2. 找到主旨類似：AWS Notification - Subscription Confirmation 的信
3. 打開信，點擊其中的 Confirm subscription 連結
4. SNS 會將訂閱狀態從 PendingConfirmation 更新為 Confirmed

在 AWS Console 確認狀態
1. 進入 AWS Console → 搜尋 SNS
2. 點選對應的 Topic（例如：docker-logs-alarm-dev-hcm-api）
3. 切換到 Subscriptions 分頁
4. 確認：
    Endpoint = 設定的 email
    Protocol = email
    Status = Confirmed

## 6. 如何在本機執行部署

以下以 dev 環境為例，其餘環境（uat / prod）類似。
6.1 初始化（Init）
```text
cd test_1/terraform/live/dev/docker-logs
terragrunt init -reconfigure
```

此步驟會：
    初始化Terraform backend（使用第3步建立的S3 + DynamoDB）
    下載AWS provider
若出現錯誤，請先確認：
    S3 bucket 與DynamoDB table是否已建立且名稱正確
    AWS CLI憑證與權限是否足夠

6.2 預覽變更（Plan）
```text
terragrunt plan
```

預期會顯示即將建立的資源：
CloudWatch Log Group
IAM Role / Policy / Attachment
CloudWatch Log Metric Filter
CloudWatch Metric Alarm
CloudWatch Dashboard
SNS Topic + Email Subscription

6.3 實際部署（Apply）
```text
terragrunt apply
```
# 出現提示時輸入 yes

部署成功後，可在 AWS Console 驗證：
CloudWatch → Log groups：/docker/dev/hcm-api
CloudWatch → Dashboards：docker-logs-dev-hcm-api
CloudWatch → Alarms：docker-error-dev-hcm-api
SNS → Topics / Subscriptions：Topic docker-logs-alarm-dev-hcm-api，email 訂閱狀態為 Confirmed
IAM → Roles：docker-logs-role-dev-hcm-api（若 create_ec2_iam_role = true）
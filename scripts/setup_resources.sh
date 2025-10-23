#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
RAW_BUCKET="ingestor-raw"
PROCESSED_BUCKET="ingestor-processed"
TABLE_NAME="files"
INGEST_FN="ingest-lambda"
API_FN="api-lambda"
API_NAME="file-api"
STAGE="prod"
ZIP_PATH="/tmp/lambdas.zip"

echo "==> [1/7] Gerando pacote das Lambdas: ${ZIP_PATH}"
python3 - << 'PY'
import os, zipfile
src='/lambdas'; dst='/tmp/lambdas.zip'
with zipfile.ZipFile(dst,'w',zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            if f.endswith('.py'):
                p=os.path.join(root,f)
                z.write(p, arcname=os.path.relpath(p, src))
print(dst)
PY

echo "==> [2/7] Criando buckets S3 (idempotente)"
awslocal s3 mb s3://${RAW_BUCKET}        2>/dev/null || true
awslocal s3 mb s3://${PROCESSED_BUCKET}  2>/dev/null || true

echo "==> [3/7] Criando tabela DynamoDB (idempotente)"
if ! awslocal dynamodb describe-table --table-name "${TABLE_NAME}" >/dev/null 2>&1; then
  awslocal dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=pk,AttributeType=S \
    --key-schema AttributeName=pk,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
fi

echo "==> [4/7] Criando/atualizando Lambdas"
if awslocal lambda get-function --function-name "${INGEST_FN}" >/dev/null 2>&1; then
  awslocal lambda update-function-code --function-name "${INGEST_FN}" --zip-file fileb://${ZIP_PATH} >/dev/null
else
  awslocal lambda create-function \
    --function-name "${INGEST_FN}" \
    --runtime python3.9 \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --handler ingest_lambda.lambda_handler \
    --zip-file fileb://${ZIP_PATH} >/dev/null
fi
if awslocal lambda get-function --function-name "${API_FN}" >/dev/null 2>&1; then
  awslocal lambda update-function-code --function-name "${API_FN}" --zip-file fileb://${ZIP_PATH} >/dev/null
else
  awslocal lambda create-function \
    --function-name "${API_FN}" \
    --runtime python3.9 \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --handler api_lambda.lambda_handler \
    --zip-file fileb://${ZIP_PATH} >/dev/null
fi

echo "==> [5/7] Gatilho S3:ObjectCreated -> ${INGEST_FN} (idempotente)"
awslocal lambda add-permission \
  --function-name "${INGEST_FN}" \
  --statement-id s3invoke \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn arn:aws:s3:::${RAW_BUCKET} >/dev/null 2>&1 || true

awslocal s3api put-bucket-notification-configuration \
  --bucket "${RAW_BUCKET}" \
  --notification-configuration "{
    \"LambdaFunctionConfigurations\": [
      {
        \"LambdaFunctionArn\": \"arn:aws:lambda:${REGION}:000000000000:function:${INGEST_FN}\",
        \"Events\": [\"s3:ObjectCreated:*\"]
      }
    ]
  }" >/dev/null

echo "==> [6/7] API Gateway (${API_NAME}) + integrações (idempotente)"
API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='${API_NAME}'].id | [0]" --output text)
if [[ -z "${API_ID}" || "${API_ID}" == "None" ]]; then
  API_ID=$(awslocal apigateway create-rest-api --name "${API_NAME}" --query "id" --output text)
fi
ROOT_ID=$(awslocal apigateway get-resources --rest-api-id "${API_ID}" --query "items[?path=='/'].id | [0]" --output text)

# /files (parent '/')
FILES_ID=$(awslocal apigateway get-resources --rest-api-id "${API_ID}" --query "items[?path=='/files'].id | [0]" --output text)
if [[ -z "${FILES_ID}" || "${FILES_ID}" == "None" ]]; then
  FILES_ID=$(awslocal apigateway create-resource --rest-api-id "${API_ID}" --parent-id "${ROOT_ID}" --path-part files --query "id" --output text)
fi
awslocal apigateway put-method --rest-api-id "${API_ID}" --resource-id "${FILES_ID}" --http-method GET --authorization-type "NONE" >/dev/null 2>&1 || true
awslocal apigateway put-integration \
  --rest-api-id "${API_ID}" --resource-id "${FILES_ID}" --http-method GET \
  --type AWS_PROXY --integration-http-method POST \
  --uri arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${REGION}:000000000000:function:${API_FN}/invocations >/dev/null

# /files/{id} (parent '/files', path-part '{id}')
FILE_ID_RES=$(awslocal apigateway get-resources --rest-api-id "${API_ID}" --query "items[?path=='/files/{id}'].id | [0]" --output text)
if [[ -z "${FILE_ID_RES}" || "${FILE_ID_RES}" == "None" ]]; then
  FILE_ID_RES=$(awslocal apigateway create-resource --rest-api-id "${API_ID}" --parent-id "${FILES_ID}" --path-part '{id}' --query "id" --output text)
fi
awslocal apigateway put-method \
  --rest-api-id "${API_ID}" --resource-id "${FILE_ID_RES}" \
  --http-method GET --authorization-type "NONE" \
  --request-parameters method.request.path.id=true >/dev/null 2>&1 || true
awslocal apigateway put-integration \
  --rest-api-id "${API_ID}" --resource-id "${FILE_ID_RES}" --http-method GET \
  --type AWS_PROXY --integration-http-method POST \
  --uri arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${REGION}:000000000000:function:${API_FN}/invocations >/dev/null

# Permissão para API GW invocar a Lambda (idempotente)
awslocal lambda add-permission \
  --function-name "${API_FN}" \
  --statement-id apigw \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com >/dev/null 2>&1 || true

# Deploy
awslocal apigateway create-deployment --rest-api-id "${API_ID}" --stage-name "${STAGE}" >/dev/null 2>&1 || true

echo "==> [7/7] Pronto!"
echo "API_ID=${API_ID}"
echo "GET /files      -> http://localhost:4566/restapis/${API_ID}/${STAGE}/_user_request_/files"
echo "GET /files/{id} -> http://localhost:4566/restapis/${API_ID}/${STAGE}/_user_request_/files/{id}"

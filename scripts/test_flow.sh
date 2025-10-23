#!/usr/bin/env bash
set -euo pipefail

API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='file-api'].id | [0]" --output text)
STAGE="prod"
FNAME="print-demo.txt"
PK="file#${FNAME}"
ENCODED_PK=$(echo "$PK" | sed 's/#/%23/g')

echo "=== PRINT 1: UPLOAD (dispara Lambda) ==="
echo "print-demo $(date -u +%FT%TZ)" > "/tmp/${FNAME}"
awslocal s3 cp "/tmp/${FNAME}" "s3://ingestor-raw/${FNAME}"

echo
echo "⏳ aguardando processamento..."
sleep 3

echo
echo "=== PRINT 2: LOGS DA LAMBDA (ingest-lambda) ==="
STREAM=$(awslocal logs describe-log-streams \
  --log-group-name /aws/lambda/ingest-lambda \
  --query "logStreams[?lastEventTimestamp!=null] | sort_by(@,&lastEventTimestamp)[-1].logStreamName" \
  --output text 2>/dev/null || true)
if [[ -n "${STREAM}" && "${STREAM}" != "None" ]]; then
  awslocal logs filter-log-events \
    --log-group-name /aws/lambda/ingest-lambda \
    --log-stream-names "${STREAM}" \
    --query "events[*].message" --output text || true
else
  echo "(nenhum evento encontrado ainda)"
fi

echo
echo "=== PRINT 3: ITEM NO DYNAMO (status=PROCESSED) ==="
awslocal dynamodb get-item \
  --table-name files \
  --key "{\"pk\":{\"S\":\"${PK}\"}}" \
  --output json

echo
echo "=== (extra) OBJETO NO BUCKET PROCESSADO ==="
awslocal s3 ls s3://ingestor-processed/ || true

echo
echo "=== PRINT 4: API RESPONDENDO (/files) ==="
if [[ -n "${API_ID}" && "${API_ID}" != "None" ]]; then
  curl -s "http://localhost:4566/restapis/${API_ID}/${STAGE}/_user_request_/files"
  echo
  echo
  echo "=== (extra) API por id (/files/{id}) ==="
  curl -s "http://localhost:4566/restapis/${API_ID}/${STAGE}/_user_request_/files/${ENCODED_PK}"
  echo
else
  echo "(!) API não encontrada. Rode /scripts/setup_resources.sh novamente."
fi

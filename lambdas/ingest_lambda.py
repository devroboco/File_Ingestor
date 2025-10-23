import boto3
import hashlib
import os
from datetime import datetime

dynamodb = boto3.resource("dynamodb", endpoint_url="http://localstack:4566")
s3 = boto3.client("s3", endpoint_url="http://localstack:4566")

TABLE_NAME = "files"
RAW_BUCKET = "ingestor-raw"
PROCESSED_BUCKET = "ingestor-processed"

def lambda_handler(event, context):
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        # Obtém metadados do S3
        obj = s3.head_object(Bucket=bucket, Key=key)
        size = obj["ContentLength"]
        etag = obj["ETag"].strip('"')
        content_type = obj.get("ContentType", "unknown")

        # Calcula SHA256
        file_obj = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        checksum = hashlib.sha256(file_obj).hexdigest()

        table = dynamodb.Table(TABLE_NAME)
        pk = f"file#{key}"

        # Cria item inicial
        table.put_item(Item={
            "pk": pk,
            "bucket": bucket,
            "key": key,
            "size": size,
            "etag": etag,
            "status": "RAW",
            "contentType": content_type,
            "checksum": checksum,
        })

        # Move para bucket processado
        s3.copy_object(
            Bucket=PROCESSED_BUCKET,
            CopySource={"Bucket": bucket, "Key": key},
            Key=key
        )
        s3.delete_object(Bucket=bucket, Key=key)

        # Atualiza status no Dynamo
        table.update_item(
            Key={"pk": pk},
            UpdateExpression="set #s=:s, processedAt=:p",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":s": "PROCESSED",
                ":p": datetime.utcnow().isoformat()
            }
        )

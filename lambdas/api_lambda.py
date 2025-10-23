import boto3
import json
from datetime import datetime
from boto3.dynamodb.conditions import Attr
from urllib.parse import unquote  # <<<<< ADICIONE ISSO

dynamodb = boto3.resource("dynamodb", endpoint_url="http://localstack:4566")
table = dynamodb.Table("files")

def _res(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str)
    }

def lambda_handler(event, context):
    path = event.get("path", "/")
    params = event.get("queryStringParameters") or {}

    if path == "/files":
        status = params.get("status") if params else None
        dt_from = params.get("from") if params else None
        dt_to = params.get("to") if params else None

        scan_kwargs = {}
        fe = None
        if status:
            fe = Attr("status").eq(status)
        if dt_from:
            fe = fe & Attr("processedAt").gte(dt_from) if fe else Attr("processedAt").gte(dt_from)
        if dt_to:
            fe = fe & Attr("processedAt").lte(dt_to) if fe else Attr("processedAt").lte(dt_to)
        if fe is not None:
            scan_kwargs["FilterExpression"] = fe

        items = table.scan(**scan_kwargs).get("Items", [])
        return _res(200, items[:100])

    elif path.startswith("/files/"):
        # Tenta pegar o id dos pathParameters (API Gateway Proxy), senão usa o path
        file_id = None
        pp = event.get("pathParameters") or {}
        if "id" in pp and pp["id"]:
            file_id = pp["id"]
        else:
            file_id = path.split("/")[-1]

        file_id = unquote(file_id)  # <<<<< DECODIFICA %23 -> #

        resp = table.get_item(Key={"pk": file_id})
        return _res(200, resp.get("Item", {}))

    return _res(404, {"message": "Not Found"})

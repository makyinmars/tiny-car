import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";
import { createService } from "./service.mjs";
const db = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TableName = process.env.TINY_CAR_TABLE;
const store = {
  async get(pk, sk) {
    return (
      (
        await db.send(
          new GetCommand({ TableName, Key: { pk, sk }, ConsistentRead: true }),
        )
      ).Item?.value || null
    );
  },
  async put(pk, sk, value) {
    await db.send(
      new PutCommand({
        TableName,
        Item: { pk, sk, value, ...(value.ttl ? { ttl: value.ttl } : {}) },
      }),
    );
  },
  async putOnce(pk, sk, value) {
    try {
      await db.send(
        new PutCommand({
          TableName,
          Item: { pk, sk, value },
          ConditionExpression: "attribute_not_exists(pk)",
        }),
      );
    } catch (error) {
      if (error.name !== "ConditionalCheckFailedException") throw error;
    }
  },
  async query(pk) {
    const rows = [];
    let cursor;
    do {
      const page = await db.send(
        new QueryCommand({
          TableName,
          KeyConditionExpression: "pk = :pk",
          ExpressionAttributeValues: { ":pk": pk },
          ExclusiveStartKey: cursor,
          ConsistentRead: true,
        }),
      );
      rows.push(...page.Items.map((item) => item.value));
      cursor = page.LastEvaluatedKey;
    } while (cursor);
    return rows;
  },
};
const service = createService(store);
export async function handler(event) {
  const headers = {
    "content-type": "application/json",
    "cache-control": "no-store",
  };
  // API Gateway's $default route forwards preflight requests too. Gateway adds
  // the configured allow-origin/headers; the handler must return a success status.
  if (event.requestContext.http.method === "OPTIONS") {
    return { statusCode: 204, headers, body: "" };
  }
  if (event.body && event.body.length > 12000)
    return {
      statusCode: 413,
      headers,
      body: JSON.stringify({ error: "Request too large." }),
    };
  let body;
  try {
    body = event.body
      ? JSON.parse(
          event.isBase64Encoded
            ? Buffer.from(event.body, "base64").toString()
            : event.body,
        )
      : {};
  } catch {
    return {
      statusCode: 400,
      headers,
      body: JSON.stringify({ error: "Invalid JSON." }),
    };
  }
  const result = await service(
    event.requestContext.http.method,
    event.rawPath,
    body,
    new URLSearchParams(event.rawQueryString),
  );
  return {
    statusCode: result.status,
    headers,
    body: JSON.stringify(result.data),
  };
}

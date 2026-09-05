import test from "node:test";
import assert from "node:assert/strict";
import { handler } from "../server/lambda.mjs";
const event = (method, rawPath, body) => ({
  requestContext: { http: { method } },
  rawPath,
  body,
});
test("API Gateway default route returns a successful CORS preflight", async () => {
  const response = await handler(event("OPTIONS", "/groups"));
  assert.equal(response.statusCode, 204);
  assert.equal(response.body, "");
  // Origin policy remains in API Gateway, not an unrestricted Lambda wildcard.
  assert.equal(response.headers["access-control-allow-origin"], undefined);
});
test("Lambda adapter returns health and rejects malformed or oversized JSON", async () => {
  assert.equal((await handler(event("GET", "/health"))).statusCode, 200);
  assert.equal((await handler(event("POST", "/groups", "{"))).statusCode, 400);
  assert.equal(
    (await handler(event("POST", "/groups", "x".repeat(12001)))).statusCode,
    413,
  );
});

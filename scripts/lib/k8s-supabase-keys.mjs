#!/usr/bin/env node
/** Emit Supabase-compatible JWT keys for in-cluster PostgREST. */
import crypto from "node:crypto";

const secret =
  process.argv[2]?.trim() ||
  process.env.JWT_SECRET?.trim() ||
  "super-secret-jwt-token-with-at-least-32-characters-long";
const exp = 1983812996;
const dbPass = process.env.POSTGRES_PASSWORD?.trim() || "postgres";
const dbHost = process.env.SUPABASE_DB_HOST?.trim() || "postgres";
const apiUrl = process.env.SUPABASE_URL?.trim() || "http://postgrest:54321";

function b64url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString("base64url");
}

function signJwt(role) {
  const header = b64url({ alg: "HS256", typ: "JWT" });
  const payload = b64url({ iss: "supabase-demo", role, exp });
  const sig = crypto.createHmac("sha256", secret).update(`${header}.${payload}`).digest("base64url");
  return `${header}.${payload}.${sig}`;
}

console.log(`SUPABASE_URL=${apiUrl}`);
console.log(`SUPABASE_ANON_KEY=${signJwt("anon")}`);
console.log(`SUPABASE_SERVICE_ROLE_KEY=${signJwt("service_role")}`);
console.log(`SUPABASE_DB_URL=postgresql://postgres:${dbPass}@${dbHost}:5432/postgres`);

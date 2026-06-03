#!/usr/bin/env node
/** Emit Supabase JWT keys and connection strings for launchpad / in-cluster stack. */
import crypto from "node:crypto";

const secret =
  process.argv[2]?.trim() ||
  process.env.JWT_SECRET?.trim() ||
  "super-secret-jwt-token-with-at-least-32-characters-long";
const exp = 1983812996;
const dbPass = process.env.POSTGRES_PASSWORD?.trim() || "postgres";
const dbHost = process.env.SUPABASE_DB_HOST?.trim() || "db";
const dbPort = process.env.SUPABASE_DB_PORT?.trim() || "5432";
const apiUrl = process.env.SUPABASE_PUBLIC_URL?.trim() || "http://127.0.0.1:30480";
const ns = process.env.SUPABASE_NAMESPACE?.trim() || "supabase";

function b64url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString("base64url");
}

function signJwt(role) {
  const header = b64url({ alg: "HS256", typ: "JWT" });
  const payload = b64url({ iss: "supabase-demo", role, exp });
  const sig = crypto.createHmac("sha256", secret).update(`${header}.${payload}`).digest("base64url");
  return `${header}.${payload}.${sig}`;
}

const anon = signJwt("anon");
const service = signJwt("service_role");
const dbUrl = `postgresql://postgres:${dbPass}@${dbHost}:${dbPort}/postgres`;
const gotrueDb = `postgres://supabase_auth_admin:${dbPass}@${dbHost}:${dbPort}/postgres`;
const pgrstDb = `postgres://authenticator:${dbPass}@${dbHost}:${dbPort}/postgres`;
const analyticsDb = `postgresql://supabase_admin:${dbPass}@${dbHost}:${dbPort}/_supabase`;

const lines = [
  `SUPABASE_NAMESPACE=${ns}`,
  `SUPABASE_PUBLIC_URL=${apiUrl}`,
  `SUPABASE_URL=${apiUrl}`,
  `API_EXTERNAL_URL=${apiUrl}`,
  `SITE_URL=${apiUrl}`,
  `POSTGRES_HOST=${dbHost}`,
  `POSTGRES_PORT=${dbPort}`,
  `POSTGRES_DB=postgres`,
  `JWT_SECRET=${secret}`,
  `ANON_KEY=${anon}`,
  `SERVICE_ROLE_KEY=${service}`,
  `SUPABASE_ANON_KEY=${anon}`,
  `SUPABASE_SERVICE_ROLE_KEY=${service}`,
  `SUPABASE_DB_URL=${dbUrl}`,
  `DATABASE_URL=${dbUrl}`,
  `GOTRUE_DB_DATABASE_URL=${gotrueDb}`,
  `PGRST_DB_URI=${pgrstDb}`,
  `POSTGRES_BACKEND_URL=${analyticsDb}`,
  `KONG_NODEPORT=30480`,
];

for (const line of lines) {
  console.log(line);
}

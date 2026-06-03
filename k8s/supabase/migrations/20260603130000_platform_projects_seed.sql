-- Seed Launchpad product rows (see docs/launchpad-products.md)
INSERT INTO public.platform_projects (slug, name) VALUES
  ('sec-agent', 'GitHub Security Agent'),
  ('search-api', 'Klaut Search API'),
  ('vault-api', 'Klaut Vault API')
ON CONFLICT (slug) DO NOTHING;

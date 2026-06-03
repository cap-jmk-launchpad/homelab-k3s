-- Seed klaut.pro product rows (see docs/klaut-pro-products.md)
INSERT INTO public.platform_projects (slug, name) VALUES
  ('sec-agent', 'GitHub Security Agent'),
  ('search-api', 'Klaut Search API'),
  ('vault-api', 'Klaut Vault API')
ON CONFLICT (slug) DO NOTHING;

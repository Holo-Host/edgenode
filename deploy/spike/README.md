# Spike: cloudflare_worker_script Feasibility

Tests whether the OpenTofu Cloudflare provider can deploy both Workers without
falling back to `wrangler deploy`. Three specific questions:

1. Can `cloudflare_worker_script` handle a TypeScript Worker that requires a
   wrangler/esbuild build step? (both Workers)
2. Can it handle the joining service Worker's cross-directory imports
   (`../../../joining-service/src/...`)?
3. Do KV namespace bindings (joining service) and D1 database bindings
   (log-collector) wire up correctly via the provider?

## Prerequisites

- Node.js 20+
- OpenTofu installed (`tofu` in PATH)
- A Cloudflare account with API token (Workers, KV, D1, Pages: Edit)
- `esbuild` installed globally or via npx: `npm install -g esbuild`

## Steps

### 1. Build both Workers

```bash
cd deploy/spike
./build.sh
```

Inspect `dist/` — both `joining.js` and `log-collector.js` should be present
and non-empty. If the joining service build fails, that answers question 2
immediately (cross-directory imports not resolvable by esbuild alone — wrangler
would be required).

### 2. Deploy via OpenTofu

```bash
cd deploy/spike/tofu
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your Cloudflare credentials
tofu init
tofu apply
```

### 3. Verify

After apply succeeds, check the Cloudflare dashboard:

- [ ] `spike-joining` Worker exists and is deployed
- [ ] `spike-joining` has `SESSIONS` KV namespace bound
- [ ] `spike-log-collector` Worker exists and is deployed
- [ ] `spike-log-collector` has `DB` D1 database bound
- [ ] Hit `https://spike-joining.<subdomain>.workers.dev/health` — expect a
      response (even a 404 is fine; a 500 with "could not route" suggests
      Worker deployed but config missing)
- [ ] Hit `https://spike-log-collector.<subdomain>.workers.dev/health` —
      same check

### 4. Clean up

```bash
tofu destroy
```

## What success looks like

All three questions answered yes → use OpenTofu for Workers in the full
deployment, no wrangler step needed.

Any question answered no → use `wrangler deploy` for Workers, OpenTofu for
Hetzner VMs, Cloudflare DNS, KV, and D1 only.

## Known risks going in

- The Cloudflare provider's `cloudflare_worker_script` expects pre-bundled JS.
  esbuild handles this for straightforward Workers but wrangler adds its own
  transforms. If the Worker uses wrangler-specific features (e.g. `__STATIC_CONTENT`
  or service bindings), esbuild alone may not suffice.
- D1 binding support in the provider was added in v4.x. Verify the provider
  version in `tofu/main.tf` matches what's available.
- The joining service imports from outside its own directory tree. esbuild
  resolves this at bundle time, but path resolution depends on running the
  build from the correct working directory (the repo root).

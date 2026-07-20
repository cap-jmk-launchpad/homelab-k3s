# Edge multi-tenant MX router

Homelab WAN has **one** public IPv4 (`77.23.124.82`) and Fritz forwards TCP **25/587/143/993** to
blackpearl (`192.168.10.33`). Multiple mail stacks share that path:

| Domain | Backend | SMTP NodePort |
|--------|---------|---------------|
| `lilangverse.xyz` | `li-mail` | **30525** |
| `bureauzilla.com` | `bureauzilla-mail` | **30725** |
| `yieldscope.d3bu7.com` | `yieldscope-mail` | **30625** |

## Design

**Option chosen:** domain-based SMTP relay on the edge (Postfix `transport_maps`).

Raw TCP cannot multiplex SMTP by hostname the way HTTP SNI can. Inbound MX always
hits `:25` on the shared WAN IP; the only reliable split is **RCPT TO domain** after
the SMTP dialog.

```
Internet :25 → Fritz → blackpearl:25
                         │
                         ▼
              postfix-mx-router (systemd)
                         │  transport_maps
         ┌───────────────┼────────────────┐
         ▼               ▼                ▼
   :30525 li-mail   :30725 bureauzilla  :30625 yieldscope
```

Submission (`:587`) and IMAP (`:143/:993`) default to **li-mail** NodePorts via iptables
`REDIRECT` (AUTH clients for lilangverse). Bureauzilla Auth SMTP uses in-cluster
ClusterIP `10.43.250.26:587`; e2e reads maildir via `kubectl` (no public IMAP required).

## Apply / rollback

On blackpearl:

```bash
cd ~/staging/homelab-k3s   # or the checked-out homelab-k3s
sudo bash scripts/edge-mail-mx-router-apply.sh
# undo:
sudo bash scripts/edge-mail-mx-router-apply.sh --rollback
```

Config lives under `/etc/postfix-mx-router/` (isolated from any system Postfix).
Unit: `postfix-mx-router.service`.

## Verify

```bash
# Banner on WAN / edge
nc -w3 127.0.0.1 25 </dev/null | head -1

# Domain routing (from blackpearl)
swaks --to e2e-tester@bureauzilla.com --from probe@example.com \
  --server 127.0.0.1 --port 25 -hl
# then:
kubectl -n bureauzilla-mail exec sts/mail -- ls /var/mail/bureauzilla.com/e2e-tester/new/

swaks --to someone@lilangverse.xyz --server 127.0.0.1 --port 25   # expect li-mail accept/reject per mailbox
```

## History

Previously `scripts/li-mail-wire-wan-forward.sh` DNATed WAN ports to **engine hostPorts**.
`li-mail` no longer binds hostPorts, so public `:25` was dead for every tenant until this
router landed.

# Deploying Pulse to Oracle Cloud (Always Free)

This gets Pulse running 24/7 on Oracle Cloud's permanent free tier, via
Docker, with no domain yet (you'll hit it at `http://<vm-ip>`). Add a domain
+ HTTPS later by flipping two env vars and putting a reverse proxy in front
— no app changes needed then.

## 0. What you're provisioning

Oracle's Always Free tier gives you (as of the current terms):

- **VM.Standard.A1.Flex (Ampere/ARM)**: up to 2 OCPUs + 12 GB RAM total,
  forever, no expiry. This is the one to use — pick 2 OCPU / 12 GB in a
  single instance (or split into two smaller ones later if you want).
- Up to 200 GB combined boot/block storage.
- 10 TB/month outbound data transfer — miles more than a hobby project
  needs.

**Gotcha to know up front:** Oracle reclaims an Always Free instance if,
over a rolling 7-day window, CPU, network, *and* memory utilization all
stay under 20%. A quiet hobby app with no traffic can trip this. Cheapest
fix once you have real users: nothing, normal traffic keeps it above the
threshold. Until then, a simple uptime pinger (e.g. UptimeRobot hitting the
homepage every few minutes, free tier) keeps it alive and doubles as
monitoring.

**Capacity gotcha:** A1 (Ampere) capacity is sometimes tight in popular
regions. If instance creation fails with an "out of capacity" error,
either retry over the next hour/day, or pick a less-contended home region
at signup if you have a choice.

## 1. Sign up

1. Go to oracle.com/cloud/free → "Start for Free."
2. Fill in account details, verify your email.
3. Billing address must match your card exactly, and use a real
   Visa/Mastercard (not a virtual/prepaid card) — Oracle does a
   verification pre-auth, not a charge, but it's picky about mismatches.
4. **Choose your Home Region carefully — it cannot be changed later**, and
   your Always Free resources live there. Pick one geographically close to
   your users if possible.

## 2. Create the VM

1. Console → **Compute → Instances → Create Instance**.
2. Name it (e.g. `pulse-prod`).
3. Under **Image and shape**: pick **Ubuntu 24.04** (or 22.04), then
   **Change shape** → **Ampere** → `VM.Standard.A1.Flex` → set 2 OCPUs /
   12 GB memory. Confirm it's tagged "Always Free eligible" before
   creating — if it isn't, you'll get billed.
4. Under **Networking**, let it create a new VCN with defaults (fine for a
   single VM) — this also gives you a public IP automatically.
5. Under **Add SSH keys**, either paste a public key you already have or
   let Oracle generate a key pair and download the private key
   (`ssh-key-*.key`) — you'll need it to log in.
6. Create the instance. Note the **public IP address** once it's running —
   you'll need it for `.env` and for SSH.

## 3. Open the firewall — twice

This trips almost everyone up: Oracle has **two separate firewalls**, and
both must allow port 80 (and 22 for SSH) or nothing gets through.

**a) Oracle's Security List (cloud-level):**

Console → your instance → **Subnet** link → **Security Lists** → default
security list → **Add Ingress Rules**:
- Source CIDR `0.0.0.0/0`, IP Protocol TCP, Destination Port `80`
- (port 22 for SSH is usually open by default — check it's there)

**b) Ubuntu's own firewall (OS-level, via iptables):**

Oracle's Ubuntu images ship with `iptables` rules (via netfilter-persistent)
that block everything except SSH by default, regardless of what the
Security List says. Once you're SSH'd in (next step), run:

```bash
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo netfilter-persistent save
```

## 4. SSH in and install Docker

```bash
ssh -i /path/to/ssh-key-*.key ubuntu@<vm-public-ip>
```

Then on the VM:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# run docker without sudo
sudo usermod -aG docker $USER
newgrp docker
```

This pulls the **arm64** Docker Engine build automatically since the VM
itself is ARM — no cross-compilation needed anywhere in this setup.

## 5. Get the code onto the VM

```bash
git clone https://github.com/Phil-Samakayi/pulse-zm.git
cd pulse-zm
cp .env.example .env
```

Edit `.env` (`nano .env`) and fill in:
- `SECRET_KEY_BASE` — generate one **locally** first with `mix phx.gen.secret`
  and paste the output in (don't run mix on the VM, you don't need an
  Elixir install there at all — Docker handles the whole build).
- `POSTGRES_PASSWORD` — any strong password.
- `PHX_HOST` — the VM's public IP from step 2.

## 6. Build and start

```bash
docker compose up -d --build
```

First build will take a few minutes (compiling the release + assets).
Watch it with `docker compose logs -f app`.

## 7. Run migrations

Once the containers are up:

```bash
docker compose run --rm app bin/pulse eval "Pulse.Release.migrate"
```

(This uses the `Pulse.Release.migrate/0` helper — included in this
deploy — since a compiled release has no `mix` binary to run
`mix ecto.migrate` with.)

## 8. Check it

Open `http://<vm-public-ip>` in a browser. You should see Pulse.

## 9. Redeploying after code changes

```bash
git pull
docker compose up -d --build
# only if there are new migrations:
docker compose run --rm app bin/pulse eval "Pulse.Release.migrate"
```

## Known follow-ups (not done yet, on purpose)

- **Email (Resend)**: `Pulse.Mailer` is still on the `Local` adapter, which
  no-ops in prod. Password reset / confirmation emails won't actually send
  until Resend is wired up — that's already on your sprint list separately.
- **Domain + HTTPS**: when you're ready, point a domain's A record at the
  VM IP, put Caddy (or nginx + certbot) in front of the app container
  instead of publishing port 80 directly, and switch `.env`'s
  `PHX_SCHEME`/`PHX_URL_PORT` (in `docker-compose.yml`) back to
  `https`/`443`. No Elixir code changes needed — that's exactly why
  `config/runtime.exs` was changed to read these from env vars.
- **Backups**: `pgdata` is a Docker named volume on the VM's boot disk.
  Nothing is backing it up off-box yet — worth a `pg_dump` cron once real
  user data exists.

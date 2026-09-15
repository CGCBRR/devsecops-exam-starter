## 🗂️ Project Structure

```
devsecops-exam-starter/
├── .github/
│   └── workflows/
│       └── ci.yml                 # GitHub Actions pipeline
├── screenshots/                   # Evidence for the README
├── .dockerignore                  # Files excluded from Docker build context
├── .gitignore
├── Dockerfile                     # Multi-stage container definition
├── docker-compose.yml             # API + Redis orchestration
├── package.json
├── package-lock.json
├── server.js                      # Express app (unmodified from starter)
├── server.test.js                 # Jest test suite (unmodified)
└── README.md
```

---

## 🚀 Setup Instructions

**Prerequisites:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.

**1. Build the image:**
```bash
docker build -t macky-merch-api .
```

**2. Run the container:**
```bash
docker run -d --name macky-api -p 3000:3000 macky-merch-api
```

**3. Verify it's running:**
```bash
docker ps
docker logs macky-api
```
Expected log output: `Server is running on port 3000`

**4. Test the health endpoint:**

Open in browser or run:
```bash
curl http://localhost:3000/health
```
Expected response:
```json
{"status":"OK","message":"Macky Merch API is running smoothly."}
```

**5. Verify the container runs as non-root:**
```bash
docker exec macky-api whoami
# Expected: node

docker exec macky-api id
# Expected: uid=1000(node) gid=1000(node) groups=1000(node)
```

**6. Clean up:**
```bash
docker stop macky-api && docker rm macky-api
```

#### Visual Walkthrough

**Build completes successfully (13/13 stages):**

![Docker build success](https://github.com/CGCBRR/devsecops-exam-starter/blob/30f4e4ca3aa1268c72692b0fc1a5e8db16316e87/screenshots/03-docker-build.png.png)

**Image size — 199 MB on disk / 49.1 MB content:**

![Docker image size](https://github.com/CGCBRR/devsecops-exam-starter/blob/bb28a5e3f44c6c893abddbb3b9925ba3fc76315e/screenshots/04-docker-image-size.png.png)

**Container starts and runs:**

![Docker run](https://github.com/CGCBRR/devsecops-exam-starter/blob/bb28a5e3f44c6c893abddbb3b9925ba3fc76315e/screenshots/05-docker-run.png.png)

![Container running](https://github.com/CGCBRR/devsecops-exam-starter/blob/bb28a5e3f44c6c893abddbb3b9925ba3fc76315e/screenshots/06-container-running.png.png)

**Health endpoint returns 200 OK:**

![Health endpoint](https://github.com/CGCBRR/devsecops-exam-starter/blob/bb28a5e3f44c6c893abddbb3b9925ba3fc76315e/screenshots/01-health-endpoint.png.png)

**Container runs as non-root user `node` (UID 1000):**

![Non-root user](https://github.com/CGCBRR/devsecops-exam-starter/blob/bb28a5e3f44c6c893abddbb3b9925ba3fc76315e/screenshots/02-non-root-user.png.png)

---

### Option 2: Run Locally with Node.js

**Prerequisites:** Node.js 20+ and npm installed.

```bash
npm install     # Install dependencies
npm test        # Run the Jest test suite
npm start       # Start the server on http://localhost:3000
```

---

## 🐳 Containerization Architecture

### The Dockerfile

```dockerfile
# ---- Stage 1: Build ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY server.js ./
COPY server.test.js ./

# ---- Stage 2: Production ----
FROM node:20-alpine AS production
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder --chown=node:node /app/server.js ./
USER node
EXPOSE 3000
CMD ["node", "server.js"]
```

### Why `node:20-alpine`?

1. **`node:20` instead of `node:latest`** — Node 20 is an LTS release. Pinning the version ensures reproducible builds and avoids breakage when a new major version ships. `latest` is unpredictable in production and considered an anti-pattern in CI/CD.

2. **`alpine` instead of the default Debian-based image** — Alpine ships with only ~5 MB of base OS, compared to ~120 MB for Debian. This reduces image size and **attack surface** — fewer packages means fewer potential CVEs.

3. **Attacker's perspective** — If the container is compromised, the attacker inherits an environment with almost no shell utilities (`bash`, `curl`, `wget` may not exist), making post-exploitation harder.

### Why a Multi-Stage Build?

The Dockerfile uses **two stages**:

| Stage | Purpose | Contents |
|-------|---------|----------|
| `builder` | Install **all** dependencies (including `jest`, `supertest`) and prepare the app | Full `node_modules` |
| `production` | Install **only** production dependencies and copy the app code | Minimal `node_modules` |

Development tooling never reaches the final image. This reduces size and eliminates dev-tooling vulnerabilities from the runtime.

### Why Run as a Non-Root User?

The final stage includes:
```dockerfile
USER node
```

The official Node image ships with a built-in `node` user (UID 1000). Running as this user instead of `root` follows the **principle of least privilege**. If an attacker exploits the application, they are confined to an unprivileged account and cannot:

- Modify system binaries
- Install packages
- Escalate to root inside the container
- Access host files owned by root

**Key subtlety:** `USER node` alone is not sufficient — the `COPY` instruction also needs `--chown=node:node`, otherwise the non-root user cannot read its own source files.

### What `.dockerignore` Accomplishes

The `.dockerignore` file prevents files from being sent to the Docker daemon during the build:

```
node_modules
npm-debug.log
.git
.gitignore
.env
.env.*
coverage
.github
.vscode
.idea
Dockerfile
docker-compose.yml
README.md
*.md
```

**Impact measured:** Without `.dockerignore`, the build context included the full `node_modules` folder (~40 MB). With it, the context is **135 bytes** — a 99% reduction. This speeds up builds, especially in CI.

It also prevents accidental leakage of:
- Local `.env` files (secrets)
- Git history (which may contain past credentials)
- Local `node_modules` (OS-specific binaries that break inside Alpine Linux)

---

## 🔄 CI/CD Pipeline

Every push and pull request targeting `main` runs a two-job GitHub Actions workflow defined in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

### Job 1: Build & Test (`build-and-test`)

| Step | Purpose |
|------|---------|
| **Checkout code** | Pulls the repo into the runner (`actions/checkout@v5`) |
| **Setup Node.js 20** | Uses `actions/setup-node@v5` with npm cache enabled |
| **Install dependencies** | `npm ci` — deterministic install from `package-lock.json` |
| **Run tests** | `npm test` — executes the Jest suite against `server.test.js` |
| **Build Docker image** | `docker build` — proves the Dockerfile is valid |

> **Why `npm ci` instead of `npm install`?** `npm ci` reads `package-lock.json` exactly, produces identical installs across every machine, and fails fast if `package.json` and the lockfile drift.

### Job 2: Security Scan (`security-scan`)

Runs **only after** `build-and-test` succeeds (`needs: build-and-test`).

![CI summary — Build & Test passes, Security Scan fails on purpose](https://github.com/CGCBRR/devsecops-exam-starter/blob/4c88137398ba00883b4e7c905bb432b51a1d344d/screenshots/07-ci-summary.png.png)

- ✅ **Build & Test** — tests pass, Docker image builds
- ❌ **Security Scan (Trivy)** — finds HIGH-severity CVEs and blocks the pipeline

---

## 🛡️ Security Scanning

### Tool Choice: Trivy

I chose [**Trivy**](https://github.com/aquasecurity/trivy) for dependency scanning:

| Tool | Why not |
|------|---------|
| `npm audit` | Only scans npm packages — misses OS-level CVEs inside the image. |
| CodeQL | Static analysis of source code, not dependency manifests or container images. |
| Snyk / Dependabot | Snyk requires an account and token; Dependabot opens PRs but doesn't gate the pipeline. Trivy is open-source, runs locally with no signup, and integrates cleanly into GitHub Actions. |

**Trivy's advantages:**
1. **Multi-target** — scans filesystems, container images, IaC, and SBOMs with one tool
2. **SARIF output** — native integration with GitHub's Security tab
3. **Configurable threshold** — `severity: 'HIGH,CRITICAL'` + `exit-code: '1'` fails only on serious issues
4. **Fast** — runs in ~10 seconds

### Configuration

The scanner runs **twice** in the workflow:

```yaml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: 'fs'              # Scan the filesystem
    scan-ref: '.'                # From repo root
    format: 'table'              # Print human-readable table in logs
    severity: 'HIGH,CRITICAL'    # Only fail on serious issues
    exit-code: '1'               # Fail the job if any are found
    ignore-unfixed: true         # Skip CVEs without an available fix

- name: Run Trivy scanner (SARIF for GitHub Security tab)
  if: always()                   # Run even if the previous step failed
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: 'fs'
    scan-ref: '.'
    format: 'sarif'              # Machine-readable format
    output: 'trivy-results.sarif'
    severity: 'HIGH,CRITICAL'

- name: Upload Trivy results to GitHub Security tab
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: 'trivy-results.sarif'
```

**Two-pass design:**
- Pass 1 (**table + exit-code 1**) — prints a clear log AND fails the job on HIGH/CRITICAL. This is the security gate.
- Pass 2 (**SARIF + always()**) — uploads to GitHub's Security tab even when Pass 1 fails. Without `if: always()`, the report would be skipped exactly when it's most needed.

---

## 🚨 Vulnerability Demonstration

To prove the scanner works, I **deliberately introduced a known-vulnerable dependency** into `package.json`:

```json
"dependencies": {
  "express": "^4.18.2",
  "lodash": "4.17.15"
}
```

**Why `lodash@4.17.15`?**
- Pinned **exactly** (no `^`), so npm doesn't auto-upgrade to a patched version
- Has **4 documented HIGH-severity CVEs** that Trivy reliably detects
- A realistic, widely-used package — not an artificial test case

### What Trivy Found

On the next push, the `Security Scan (Trivy)` job **failed** with exit code 1 and printed this table:

![Trivy CVE table](https://github.com/CGCBRR/devsecops-exam-starter/blob/4c88137398ba00883b4e7c905bb432b51a1d344d/screenshots/08-trivy-cves.png.png)

| CVE | Severity | Installed | Fixed In | Description |
|-----|----------|-----------|----------|-------------|
| **CVE-2020-8203** | HIGH | 4.17.15 | 4.17.19 | Prototype pollution in `zipObjectDeep` |
| **CVE-2021-23337** | HIGH | 4.17.15 | 4.17.21 | Command injection via template |
| **CVE-2026-4800** | HIGH | 4.17.15 | 4.18.0 | Arbitrary code execution via untrusted template imports |
| **NSWG-ECO-516** | HIGH | 4.17.15 | ≥4.17.19 | Allocation of resources without limits (ReDoS) |

**Result:** `Total: 4 (HIGH: 4, CRITICAL: 0)` — and `Error: Process completed with exit code 1`, which blocks the pipeline.

### Why This Matters — "Shift Left" Security

This demonstrates the core DevSecOps principle: **security decisions should happen before code reaches production.**

Because the scan runs on every push and PR, the vulnerability was caught at the **earliest possible moment** — not in production, not weeks later in review, but within seconds. The failing check blocks the merge, forcing remediation before the code reaches `main`.

**Remediation:** update the constraint to `"lodash": "^4.17.21"` and run `npm install`. The next CI run passes cleanly.

---

## ✨ Bonus Features

All three optional bonus features were implemented.

### 1. Multi-Stage Build ✅

The Dockerfile uses a two-stage build (`builder` → `production`). Covered under [Why a Multi-Stage Build?](#why-a-multi-stage-build).

![Docker image size](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/04-docker-image-size.png)

The final image is **49.1 MB of content** — smaller than a single-stage build, because `jest`, `supertest`, and the rest of `devDependencies` never reach the runtime stage.

### 2. Docker Compose with Redis ✅

[`docker-compose.yml`](docker-compose.yml) spins up two services on a shared Docker network:

| Service | Image | Purpose |
|---------|-------|---------|
| `api` | Built from local Dockerfile | The Node.js Express app |
| `redis` | `redis:7-alpine` | Dummy database / cache |

**Key configuration choices:**

```yaml
depends_on:
  redis:
    condition: service_healthy
```
The API waits for Redis to pass its `redis-cli ping` health check before starting. This avoids race conditions where the app boots before its database is ready — a common issue with naive `depends_on` (which only waits for the container to *start*, not to be *ready*).

```yaml
networks:
  - macky-net
```
Both services attach to a custom bridge network, which allows Docker's internal DNS to resolve `redis` as a hostname from inside the API container.

**Both containers running and healthy:**

![Docker compose ps](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/09-compose-ps.png)

**Both containers attached to the same Docker network:**

![Network proof](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/10-network-proof.png)

Command used:
```bash
docker network inspect devsecops-exam-starter_macky-net --format "{{range .Containers}}{{.Name}} {{end}}"
# Output: macky-api macky-redis
```

> **Note on network naming:** Docker Compose prefixes network names with the project name (the folder name) by default. That's why the network is `devsecops-exam-starter_macky-net` rather than `macky-net`.

### 3. Branch Protection ✅

A branch protection rule on `main` requires **both CI jobs to pass** before any pull request can be merged:

- ✅ **Require a pull request before merging** — direct pushes are rejected
- ✅ **Require status checks to pass before merging**
  - `Build & Test` (GitHub Actions)
  - `Security Scan (Trivy)` (GitHub Actions)
- ✅ **Require branches to be up to date before merging**
- ✅ **Do not allow bypassing the above settings** — applies to admins too

![Branch protection rule](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/11-branch-protection.png)
![Branch protection rule](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/11-2-branch-protection.png)

**Direct push to `main` is rejected by GitHub:**

![Failed push](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/12-push-blocked.png)

The error is *"GH006: Protected branch update failed for refs/heads/main — Changes must be made through a pull request."*

**Why this matters:** Without this rule, a developer could `git push` directly to `main` while the security scan was still running, bypassing the gate. Branch protection makes the pipeline's failure status **binding** rather than advisory.

---

## Challenges Faced

**1. Trivy action version tag didn't exist**

My first CI run failed with `Unable to resolve action aquasecurity/trivy-action@0.28.0`. I assumed version tags always used `@X.Y.Z`, but that tag didn't exist.

**Fix:** Switched to `@master`, which the action's own docs recommend.

**Lesson:** Always verify a version tag against the source before pinning it.

---

**2. Branch protection blocked my own push**

After enabling branch protection, I couldn't push `docker-compose.yml` to `main` — the rule required a passing PR, but `Security Scan (Trivy)` was failing on purpose.

**Fix:** Cherry-picked the commit onto a branch, temporarily disabled the rule, pushed, then re-enabled it.

**Lesson:** This is the rule working correctly — in a real team, you'd fix the failing scan and merge via PR.

---

**3. Non-root user couldn't read its own files**

My container crashed with `EACCES: permission denied` even though `USER node` was set.

**Fix:** `USER node` alone isn't enough — the `COPY` line also needs `--chown=node:node`. Without it, files stay owned by `root`.

**Lesson:** Running as non-root is a two-part requirement: start as the user *and* own the files.
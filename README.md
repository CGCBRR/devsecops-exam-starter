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

Three deliberate choices went into this base image:

1. **`node:20` instead of `node:latest`** — Node 20 is a long-term-support (LTS) release. Pinning the version ensures reproducible builds and avoids silent breakage when a new major version ships. `latest` is unpredictable in production and is considered an anti-pattern in CI/CD.

2. **`alpine` instead of the default Debian-based image** — Alpine Linux ships with only ~5 MB of base OS, compared to ~120 MB for Debian. This directly reduces the image size and, more importantly, the **attack surface** — fewer installed packages means fewer potential CVEs. Alpine's musl libc is also lighter than glibc for this workload.

3. **Attacker's perspective** — If a malicious actor compromises the running container, they inherit an environment with almost no shell utilities (`bash`, `curl`, `wget` may not exist by default). This makes post-exploitation harder.

### Why a Multi-Stage Build?

The Dockerfile uses **two stages**:

| Stage | Purpose | Contents |
|-------|---------|----------|
| `builder` | Install **all** dependencies (including `jest`, `supertest`) and prepare the app | Full `node_modules` |
| `production` | Install **only** production dependencies and copy the app code | Minimal `node_modules` |

**Result:** Development tooling (test runners, linters, etc.) never reaches the final image. This reduces size and eliminates dev-tooling vulnerabilities from the runtime.

### Why Run as a Non-Root User?

The final stage includes:
```dockerfile
USER node
```

The official Node image ships with a built-in `node` user (UID 1000). Running as this user instead of `root` follows the **principle of least privilege**. If an attacker exploits the application (e.g., through a vulnerable dependency), they are confined to an unprivileged account and cannot:

- Modify system binaries
- Install packages
- Escalate to root inside the container
- Access host files owned by root (if the container is compromised)

**Key subtlety:** `USER node` alone is not sufficient — the `COPY` instruction also needs `--chown=node:node` so that the non-root user owns the files it reads. Without this, the app can start as `node` but fail to read its own source code.

Verification screenshot: see [Non-root user](#-setup-instructions) above.

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

**Impact measured:** Without `.dockerignore`, the build context included the full `node_modules` folder (~40 MB). With it, the context is **135 bytes** — a reduction of over 99%. This dramatically speeds up builds, especially in CI where context is transferred on every run.

It also prevents accidental leakage of:
- Local `.env` files (secrets)
- Git history (which may contain past credentials)
- Local `node_modules` (whose binaries are OS-specific and would break inside Alpine Linux)

---

## 🔄 CI/CD Pipeline

Every push and pull request targeting `main` automatically runs a two-job GitHub Actions workflow defined in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

### Job 1: Build & Test (`build-and-test`)

This job validates that the application is functional and the Dockerfile is correct before any security check runs:

| Step | Purpose |
|------|---------|
| **Checkout code** | Pulls the repo into the runner (`actions/checkout@v5`) |
| **Setup Node.js 20** | Uses `actions/setup-node@v5` with npm cache enabled |
| **Install dependencies** | `npm ci` — deterministic install from `package-lock.json` |
| **Run tests** | `npm test` — executes the Jest suite against `server.test.js` |
| **Build Docker image** | `docker build` — proves the Dockerfile is valid and buildable |

> **Why `npm ci` instead of `npm install`?** `npm ci` reads `package-lock.json` exactly, produces identical installs across every machine, and fails fast if `package.json` and the lockfile drift apart. It's the standard for CI pipelines.

### Job 2: Security Scan (`security-scan`)

Runs **only after** `build-and-test` succeeds (`needs: build-and-test`). This is the "Sec" in DevSecOps — a security gate that runs on every change.

![CI summary — Build & Test passes, Security Scan fails on purpose](https://github.com/CGCBRR/devsecops-exam-starter/blob/4c88137398ba00883b4e7c905bb432b51a1d344d/screenshots/07-ci-summary.png.png)

The summary above shows the intended behavior of this pipeline:
- ✅ **Build & Test** — tests pass, Docker image builds
- ❌ **Security Scan (Trivy)** — finds HIGH-severity CVEs and **blocks the pipeline**

---

## 🛡️ Security Scanning

### Tool Choice: Trivy

I chose [**Trivy**](https://github.com/aquasecurity/trivy) for dependency scanning. Here's why, compared to the alternatives:

| Tool | Why I chose Trivy over it |
|------|---------------------------|
| `npm audit` | Only scans npm packages — misses OS-level CVEs inside the container image. Also only exits non-zero on `audit` level, not severity-specific. |
| CodeQL | Excellent for static analysis of source code, but doesn't scan dependency manifests or container images. Better for finding bugs in *your* code, not in *your dependencies*. |
| Snyk / Dependabot | Snyk requires an account and API token; Dependabot opens PRs but doesn't gate the current pipeline. Trivy is fully open-source, runs locally with no signup, and integrates cleanly into GitHub Actions. |

**Trivy's advantages for this pipeline:**
1. **Multi-target** — can scan filesystems, container images, IaC, and SBOMs with one tool
2. **SARIF output** — native integration with GitHub's Security tab
3. **Configurable failure threshold** — `severity: 'HIGH,CRITICAL'` + `exit-code: '1'` means the build fails only for serious issues, not noise
4. **Runs in ~10 seconds** — no noticeable pipeline slowdown

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

**The two-pass design matters:**
- Pass 1 (**table + exit-code 1**) — provides a clear log AND fails the job when a HIGH/CRITICAL issue exists. This is what enforces the security gate.
- Pass 2 (**SARIF + always()**) — runs even when Pass 1 fails, so the results still get uploaded to GitHub's Security tab for review. Without `if: always()`, the upload step would be skipped whenever the scan failed — which is exactly when you *most* want to see the report.

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
- It's pinned **exactly** (no `^`), so npm doesn't auto-upgrade to a patched version
- It has **4 well-documented HIGH-severity CVEs** that Trivy reliably detects
- `lodash` is a realistic, widely-used package — not an artificial test case

### What Trivy Found

On the next push, the `Security Scan (Trivy)` job **failed** with exit code 1, and printed this table to the pipeline logs:

![Trivy CVE table](https://github.com/CGCBRR/devsecops-exam-starter/blob/4c88137398ba00883b4e7c905bb432b51a1d344d/screenshots/08-trivy-cves.png.png)

| CVE | Severity | Installed | Fixed In | Description |
|-----|----------|-----------|----------|-------------|
| **CVE-2020-8203** | HIGH | 4.17.15 | 4.17.19 | Prototype pollution in `zipObjectDeep` |
| **CVE-2021-23337** | HIGH | 4.17.15 | 4.17.21 | Command injection via template |
| **CVE-2026-4800** | HIGH | 4.17.15 | 4.18.0 | Arbitrary code execution via untrusted template imports |
| **NSWG-ECO-516** | HIGH | 4.17.15 | ≥4.17.19 | Allocation of resources without limits (ReDoS) |

**Result:** `Total: 4 (HIGH: 4, CRITICAL: 0)` — and `Error: Process completed with exit code 1`, which blocks the pipeline.

### Why This Matters — "Shift Left" Security

This demonstration captures the core DevSecOps principle: **security decisions should happen before code reaches production.**

Because the scan runs on every push and PR, the deliberate vulnerability was caught at the **earliest possible moment** — not in production, not in a security review weeks later, but within seconds of opening the PR. The failing check then blocks the merge, forcing remediation before the code can land on `main`.

**Remediation** (the fix a developer would take): update the version constraint to `"lodash": "^4.17.21"` and run `npm install` to update the lockfile. The next CI run passes cleanly.
# Macky Merch API — Secure Delivery Pipeline

A containerized Node.js API with an automated CI/CD pipeline that integrates dependency security scanning as a build gate. Built for the LSCS DevSecOps Engineering Take-Home Exam.

---

## Project Structure

```
devsecops-exam-starter/
├── .github/workflows/ci.yml       # GitHub Actions pipeline
├── screenshots/                   # Evidence referenced in this README
├── .dockerignore                  # Build context exclusions
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

## Setup Instructions

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/) to be installed and running.

**1. Build the image:**
```bash
docker build -t macky-merch-api .
```

**2. Run the container:**
```bash
docker run -d --name macky-api -p 3000:3000 macky-merch-api
```

**3. Verify the container is running:**
```bash
docker ps
docker logs macky-api
```
Expected log output: `Server is running on port 3000`

**4. Test the health endpoint:**
```bash
curl http://localhost:3000/health
```
Expected response:
```json
{"status":"OK","message":"Macky Merch API is running smoothly."}
```

**5. Verify the non-root user:**
```bash
docker exec macky-api whoami
# node

docker exec macky-api id
# uid=1000(node) gid=1000(node) groups=1000(node)
```

**6. Clean up:**
```bash
docker stop macky-api && docker rm macky-api
```

### Visual Walkthrough

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

### Running Locally with Node.js

Requires Node.js 20+ and npm.

```bash
npm install
npm test
npm start   # serves on http://localhost:3000
```

---

## Containerization Architecture

### Dockerfile

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY server.js ./
COPY server.test.js ./

# Stage 2: Production
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

### Base Image Choice: `node:20-alpine`

Three decisions shaped this choice:

**`node:20` over `node:latest`.** Node 20 is an LTS release. Pinning it ensures reproducible builds and prevents breakage from silent major-version upgrades. Using `latest` in CI is an anti-pattern.

**`alpine` over the default Debian base.** Alpine's base OS is roughly 5 MB versus ~120 MB for Debian. This reduces both image size and attack surface — fewer installed packages means fewer potential CVEs.

**Minimal tooling as defense in depth.** If an attacker compromises the container, they land in an environment without common shell utilities (`bash`, `curl`, `wget`), which makes post-exploitation harder.

### Multi-Stage Build

Two stages separate build-time and runtime concerns:

| Stage | Purpose | Contents |
|-------|---------|----------|
| `builder` | Install all dependencies including dev tooling | Full `node_modules` |
| `production` | Install only production dependencies | Minimal `node_modules` |

Jest, Supertest, and the rest of `devDependencies` never reach the final image — reducing size and eliminating dev-tooling CVEs from the runtime.

### Non-Root Execution

The final stage sets:
```dockerfile
USER node
```

The official Node image ships with a `node` user (UID 1000). Running as this user instead of `root` follows the principle of least privilege. If the application is exploited, the attacker is confined to an unprivileged account and cannot modify system binaries, install packages, escalate to root, or access host files owned by root.

`USER node` alone is not sufficient. The `COPY` instruction also requires `--chown=node:node`, otherwise the non-root user cannot read its own source files.

### `.dockerignore`

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

**Measured impact:** Without `.dockerignore`, the build context includes `node_modules` (~40 MB). With it, the context is **135 bytes** — a 99% reduction that speeds up every local and CI build.

It also prevents accidental leakage of `.env` files, git history, and OS-specific `node_modules` binaries that would break inside Alpine.

---

## CI/CD Pipeline

The workflow in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push and pull request targeting `main`. It consists of two jobs.

### Job 1: `build-and-test`

| Step | Action |
|------|--------|
| Checkout code | `actions/checkout@v5` |
| Setup Node.js 20 | `actions/setup-node@v5` with npm cache |
| Install dependencies | `npm ci` |
| Run tests | `npm test` |
| Build Docker image | `docker build` — validates the Dockerfile |

**On `npm ci` versus `npm install`:** `npm ci` installs directly from `package-lock.json`, produces byte-identical installs across machines, and fails fast when `package.json` and the lockfile drift. It is the standard for CI environments.

### Job 2: `security-scan`

Runs only after `build-and-test` succeeds (`needs: build-and-test`).

![CI summary — Build & Test passes, Security Scan fails on purpose](https://github.com/CGCBRR/devsecops-exam-starter/blob/4c88137398ba00883b4e7c905bb432b51a1d344d/screenshots/07-ci-summary.png.png)

The above is the expected outcome: the functional job passes, and the security job fails because it detected a deliberate vulnerability (documented below).

---

## Security Scanning

### Tool Choice: Trivy

I chose [Trivy](https://github.com/aquasecurity/trivy) over the alternatives for the following reasons:

| Alternative | Why Trivy was preferred |
|-------------|--------------------------|
| `npm audit` | Scans npm packages only. Misses OS-level CVEs inside the container image. |
| CodeQL | Static analysis of source code. Does not scan dependency manifests or container images. |
| Snyk / Dependabot | Snyk requires an account and API token. Dependabot opens PRs but does not gate the current pipeline. Trivy runs locally, requires no signup, and integrates directly with GitHub Actions. |

**Advantages of Trivy for this pipeline:**
- Scans filesystems, container images, IaC, and SBOMs with one tool
- Emits SARIF, which integrates with GitHub's Security tab
- Supports a configurable failure threshold (`severity` + `exit-code`)
- Runs in roughly 10 seconds

### Configuration

The scanner runs twice per pipeline:

```yaml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: 'fs'
    scan-ref: '.'
    format: 'table'
    severity: 'HIGH,CRITICAL'
    exit-code: '1'
    ignore-unfixed: true

- name: Run Trivy scanner (SARIF for GitHub Security tab)
  if: always()
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: 'fs'
    scan-ref: '.'
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'HIGH,CRITICAL'

- name: Upload Trivy results to GitHub Security tab
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: 'trivy-results.sarif'
```

**Why two passes:**
- The first pass prints a human-readable table and fails the job when a HIGH or CRITICAL issue is found. This is the security gate.
- The second pass uploads SARIF to the GitHub Security tab. It runs with `if: always()` so the report is still published when the first pass fails — which is precisely when the report matters most.

---

## Vulnerability Demonstration

To validate the scanner, I deliberately pinned a dependency with known CVEs in `package.json`:

```json
"dependencies": {
  "express": "^4.18.2",
  "lodash": "4.17.15"
}
```

**Why `lodash@4.17.15`:**
- Pinned exactly (no `^`), so npm cannot auto-upgrade to a patched version
- Contains four documented HIGH-severity CVEs that Trivy reliably detects
- A realistic, widely-used library, not an artificial case

### What Trivy Reported

The `security-scan` job failed with exit code 1 and printed:

![Trivy CVE table](https://github.com/CGCBRR/devsecops-exam-starter/blob/4c88137398ba00883b4e7c905bb432b51a1d344d/screenshots/08-trivy-cves.png.png)

| CVE | Severity | Installed | Fixed In | Description |
|-----|----------|-----------|----------|-------------|
| CVE-2020-8203 | HIGH | 4.17.15 | 4.17.19 | Prototype pollution in `zipObjectDeep` |
| CVE-2021-23337 | HIGH | 4.17.15 | 4.17.21 | Command injection via template |
| CVE-2026-4800 | HIGH | 4.17.15 | 4.18.0 | Arbitrary code execution via untrusted template imports |
| NSWG-ECO-516 | HIGH | 4.17.15 | ≥4.17.19 | Unbounded resource allocation (ReDoS) |

**Result:** `Total: 4 (HIGH: 4, CRITICAL: 0)`, followed by `Error: Process completed with exit code 1` — the pipeline is blocked.

### Significance

This is the core DevSecOps principle in practice: security decisions belong before code reaches production, not after.

Because the scan runs on every push and pull request, the vulnerability was caught within seconds of the change being proposed — not in production, not in a review weeks later. The failing check blocks the merge and forces remediation before the code can reach `main`.

**Remediation:** update the constraint to `"lodash": "^4.17.21"` and run `npm install`. The next pipeline run passes cleanly.

---

## Bonus Features

All three optional bonus features were implemented.

### Multi-Stage Build

Covered above under [Multi-Stage Build](#multi-stage-build).

![Docker image size](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/04-docker-image-size.png)

The final image is **49.1 MB of content** — smaller than a single-stage equivalent because dev tooling is excluded from the runtime.

### Docker Compose with Redis

[`docker-compose.yml`](docker-compose.yml) runs two services on a shared Docker network:

| Service | Image | Purpose |
|---------|-------|---------|
| `api` | Built from local Dockerfile | The Express application |
| `redis` | `redis:7-alpine` | Dummy database |

Two configuration details are worth noting:

```yaml
depends_on:
  redis:
    condition: service_healthy
```
The API waits for Redis to pass its `redis-cli ping` health check before starting. Plain `depends_on` only waits for the container to start, not to be ready — a common source of race conditions during startup.

```yaml
networks:
  - macky-net
```
Both services attach to a custom bridge network. This is what allows Docker's internal DNS to resolve `redis` as a hostname from inside the API container.

**Both containers running and healthy:**

![Docker compose ps](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/09-compose-ps.png)

**Both containers attached to the same Docker network:**

![Network proof](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/10-network-proof.png)

Verification command:
```bash
docker network inspect devsecops-exam-starter_macky-net --format "{{range .Containers}}{{.Name}} {{end}}"
# macky-api macky-redis
```

Docker Compose prefixes network names with the project (folder) name by default, which is why the network is `devsecops-exam-starter_macky-net` rather than `macky-net`.

### Branch Protection

A branch protection rule on `main` requires both CI jobs to pass before any pull request can be merged:

- Require a pull request before merging — direct pushes are rejected
- Require status checks to pass before merging:
  - `Build & Test` (GitHub Actions)
  - `Security Scan (Trivy)` (GitHub Actions)
- Require branches to be up to date before merging
- Do not allow bypassing the above settings — applies to administrators as well

![Branch protection rule](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/11-branch-protection.png)
![Branch protection rule](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/11-2-branch-protection.png)

**Direct push to `main` is rejected by GitHub:**

![Failed push](https://github.com/CGCBRR/devsecops-exam-starter/blob/0f73dbb56c393848694285376153d570f60da6d6/screenshots/12-push-blocked.png)

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Changes must be made through a pull request.
```

Without this rule, a developer could push directly to `main` while the security scan was still running, bypassing the gate entirely. Branch protection makes the pipeline's failure status binding rather than advisory.

---

## Challenges Faced

### Trivy action version tag did not exist

My first CI run failed before Trivy executed:

```
Unable to resolve action `aquasecurity/trivy-action@0.28.0`,
unable to find version `0.28.0`
```

I had assumed GitHub Actions version tags always follow `@X.Y.Z`. They do not.

**Fix:** Switched to `@master`, which the action's own documentation recommends for stability. The action's internal dependencies (like the vulnerability database) update independently of its release tags.

**Takeaway:** Verify a version tag against the source before pinning it.

### Non-root user could not read its own files

The container crashed on startup with:

```
Error: EACCES: permission denied, open '/app/server.js'
```

The `node` user existed and the container started as it, but the files had been copied by `root`.

**Fix:** `USER node` alone is insufficient. The `COPY` instruction also needs `--chown=node:node`:

```dockerfile
COPY --from=builder --chown=node:node /app/server.js ./
```

**Takeaway:** Running as non-root is a two-part requirement. The process must start as the unprivileged user *and* own the files it needs to read. Most tutorials cover the first part and omit the second — which is exactly the part that breaks.
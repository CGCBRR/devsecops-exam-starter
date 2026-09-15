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
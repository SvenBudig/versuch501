---
marp: true
theme: default
paginate: true
header: 'Supply Chain Security Lab'
footer: 'Phase 1: Security Scanning'
style: |
  section {
    font-size: 20px;
  }
  h1 {
    font-size: 40px;
  }
  h2 {
    font-size: 30px;
  }
  code {
    font-size: 14px;
  }
  pre {
    font-size: 14px;
  }
---

# Supply Chain Security Lab
## Hands-On Exercises

**Learn by Building**
Secure your software supply chain from source to deployment

---

## Prerequisites - Warm-Up

**Install Required Tools:**
```bash
# Install task runner
sudo snap install task --classic 2>&1 && task --version

# Install gh cli
curl -sS https://webi.sh/gh | sh;
echo 'source ~/.config/envman/PATH.env' >> ~/.zshrc
source ~/.config/envman/PATH.env

# Install gitsign
cd /tmp && wget https://github.com/sigstore/gitsign/releases/download/v0.13.0/gitsign_0.13.0_linux_amd64
sudo mv gitsign_0.13.0_linux_amd64 /usr/local/bin/gitsign && sudo chmod +x /usr/local/bin/gitsign

# Verify all tools
task --version  # Should show v3.x.x
docker --version
git --version
gh --version
gitsign --version  # Should show v0.13.0
```

---

# Step 0: Setup Git & Fork Repository

```bash
# Authenticate & setup SSH
gh auth login  # Choose: GitHub.com → SSH → Generate new key → Browser auth

# Clone the lab repository
git clone git@github.com:thi-ics/supply-chain-lab.git
cd supply-chain-lab

# Manual fork: Change remote to YOUR fork (replace YOUR_USERNAME)
git remote set-url origin git@github.com:YOUR_USERNAME/supply-chain-lab.git
git remote -v  # Verify origin points to your fork

# Configure identity (use YOUR email)
export EMAIL="your.email@example.com"
git config --global user.name "Your Name"
git config --global user.email "$EMAIL"

# Configure gitsign
git config --local gpg.x509.program gitsign
git config --local gpg.format x509
git config --local commit.gpgsign true
git config --local gitsign.connectorID https://github.com/login/oauth
```

---

# Step 1: Test Signed Commit

```bash
echo "Hello My Favorite Lab Ever :)" > my_first_signed_commit.txt
git add my_first_signed_commit.txt
git commit -m "feat: my first keyless signed commit"
# Device flow: Copy OAuth URL → browser auth → paste code
git push origin main
```

**Inspect certificate:**
```bash
UUID=$(task exec -- rekor-cli search --email $EMAIL | tail -1)
task exec -- rekor-cli get --uuid $UUID --format json | jq -r '.Body.DSSEObj.signatures[0].verifier' | base64 -d | openssl x509 -text -noout
```

---

# Phase 1: Security Scanning

**Learning Goals:**
- Detect vulnerabilities across 5 categories
- Practice remediation techniques
- Build foundation for SLSA Level 1

**📖 Theory Reference:** See CONCEPTS.md - Section 3: Security Scanning

---

# Exercise 1.1: Run Security Scans

**Your Task:** Run all security scans to discover intentional vulnerabilities

**Commands:**
```bash
task scan-all
```

---

# Exercise 1.1: Individual Scans

Run scans separately:
```bash
task scan-source
task scan-deps
task scan-dockerfile
task scan-iac 
task scan-manifests
```

Build and scan the container image:
```bash
task build-image
task scan-image
```

---

# Exercise 1.1: Expected Results

**What you should see:**
- ❌ Source code: Hardcoded secrets, SQL injection
- ❌ Dependencies: Vulnerable Flask 2.0.1 (CVE-2023-30861)
- ❌ Dockerfile: Running as root (HIGH), missing HEALTHCHECK (LOW)
- ❌ IaC: 6 failures (4 S3 public access, 1 SSH from 0.0.0.0/0, 1 unattached security group)
- ❌ K8s: 3 HIGH (privileged mode, running as root, read-only filesystem)
- ❌ Image: 907 vulnerabilities (56 CRITICAL, 851 HIGH) in Python 3.8 base image (~3900 total if including all severities)

**Questions to Consider:**
- Which vulnerabilities are most critical?
- What's the attack surface for each issue?
- How do these scans complement each other?

---

# Exercise 1.2: Fix Source Code Vulnerabilities
## Part 1/6

**File:** `src/app/main.py`

**Vulnerabilities Found:**
- Line 7: Hardcoded API token `sk-1234567890abcdef`
- Line 13: SQL injection via string formatting

---

# Exercise 1.2: Hints

**Fix #1 - Hardcoded Secret:**
- Use environment variable: `os.environ.get('API_TOKEN', 'default')`

**Fix #2 - SQL Injection:**
- Use parameterized query: `query = "SELECT * FROM users WHERE id = ?"`
- Pass parameters: `conn.execute(query, (user_id,))`

**Verify:** `task scan-source`

---

# Exercise 1.2: Fix Dependency Vulnerabilities
## Part 2/6

**File:** `src/app/pyproject.toml`

**Vulnerability:** Flask 2.0.1 (CVE-2023-30861)

**Fix:** Update Flask to 3.1.0+
```toml
  "flask>=3.1.0",
```

**Verify:** `task build && task scan-deps`

---

# Exercise 1.3: Fix Container Vulnerabilities
## Part 3/6

**File:** `src/docker/Dockerfile`

**Vulnerabilities Found:**
- Outdated base image `python:3.8` (907 HIGH/CRITICAL, ~3900 total)
- Running as root (HIGH)
- Missing HEALTHCHECK (LOW)

---

# Exercise 1.3: Hints

**Fix #1 - Base Image:**
- Change to `FROM python:3.12-slim`
- Reduces 907 → 3 HIGH vulnerabilities

**Fix #2 - Root User:**
```dockerfile
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app
USER appuser
```

**Fix #3 - Filter LOW Severity:**
- Edit `Taskfile.yml` task `_scan-dockerfile`
- Add `--severity MEDIUM,HIGH,CRITICAL` to trivy command
- Filters out LOW severity issues (e.g., HEALTHCHECK)

**Verify:** `task scan-dockerfile && task build-image && task scan-image`

---

# Exercise 1.4: Fix IaC Vulnerabilities
## Part 3/5

**File:** `src/iac/main.tf`

**Vulnerabilities Found (6 failures):**
- Public S3 bucket (4 checks: block_public_acls, block_public_policy, ignore_public_acls, restrict_public_buckets = false)
- SSH accessible from 0.0.0.0/0
- Security group not attached (CKV2_AWS_5 - infrastructure completeness check)

---

# Exercise 1.4: Hints

**Fix #1 - S3 Bucket:**
- Set all 4 public access blocks to `true`

**Fix #2 - SSH Access:**
- Restrict CIDR to specific IP: `["203.0.113.0/24"]`

**Fix #3 - Skip Infrastructure Check:**
The CKV2_AWS_5 check requires security groups to be attached to EC2 instances. Since this is a standalone example, we can skip this check:
- Add `--skip-check CKV2_AWS_5` to the checkov command in `Taskfile.yml` (line 297)

**Verify:** `task scan-iac` (expect 0 failures)

---

# Exercise 1.5: Fix K8s Vulnerabilities
## Part 4/5

**File:** `src/k8s/deployment.yaml`

**Vulnerabilities Found (3 HIGH):**
- `privileged: true` (container can access host resources)
- `runAsUser: 0` (running as root)
- Missing `readOnlyRootFilesystem` (filesystem tampering risk)

---

# Exercise 1.5: Hints

**Step 1: Add pod-level securityContext (line 14, after `spec:`):**
```yaml
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
```

**Step 2: Fix container securityContext (lines 20-22):**
```yaml
        securityContext:
          privileged: false
          runAsNonRoot: true
          readOnlyRootFilesystem: true
```

**Verify:** `task scan-manifests` (expect 0 HIGH/CRITICAL)

---

# Exercise 1.6: Build Secure Application
## Part 5/5

**Your Task:** Build the now-secure application and container

**Commands:**
```bash
task build
task build-image
```

**Expected Output:**
- ✅ Application built successfully
- ✅ Container image created
- ✅ All security fixes applied

---

# Phase 1 Summary

**What You Accomplished:**
✅ Scanned 5 vulnerability categories  
✅ Fixed source code (secrets, injection)  
✅ Secured container (base image, user)  
✅ Hardened infrastructure (S3, SSH)  
✅ Locked down Kubernetes (privileges)

**Next: Phase 2 - Attestations & Provenance**

*📖 For defense-in-depth and SLSA concepts, see CONCEPTS.md Sections 1 & 4*

---

# Next: Phase 2
## Attestations & Provenance

**Coming Up:**
- Generate SLSA provenance
- Create SBOM attestations
- Wrap vulnerability reports
- Learn in-toto format

**Why This Matters:**
Scanning finds problems, but attestations **prove** you fixed them and **document** your secure build process.

---

# Checkpoint

**Before proceeding, verify:**
- [ ] All scans pass after your fixes
- [ ] `task test` passes
- [ ] Application builds successfully
- [ ] Container image builds successfully

**Ready?** Move to Phase 2 when checkpoint complete

---

# Final: Commit Your Lab Work

```bash
git add src/app/main.py src/app/pyproject.toml src/docker/Dockerfile \
        src/iac/main.tf src/k8s/deployment.yaml Taskfile.yml
git commit -m "fix: resolve all Phase 1 security vulnerabilities"
git push origin main
```

**Verify both commits in Rekor:**
```bash
task exec -- rekor-cli search --email $EMAIL  # Should show 2 entries

# Inspect latest certificate
UUID=$(task exec -- rekor-cli search --email $EMAIL | tail -1)
task exec -- rekor-cli get --uuid $UUID --format json | jq -r '.Body.DSSEObj.signatures[0].verifier' | base64 -d | openssl x509 -text -noout
```

**✅ Phase 1 Complete** - Move to Phase 2

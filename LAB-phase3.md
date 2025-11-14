---
marp: true
theme: default
paginate: true
header: 'Supply Chain Security Lab'
footer: 'Phase 3: Keyless Signing & Transparency'
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

# Phase 3: Keyless Signing & Transparency

**Learning Goals:**
- Sign container images with keyless signing
- Attach signed attestations
- Explore signed artifacts and certificates
- Verify signatures in Rekor transparency log

**Prerequisites:**
- Phase 2 completed
- Attestation files in `attestations/` directory
- Container image buildable

**Tool Access:** All commands use `task exec -- <command>` to run inside the supply-chain-tools container

**📖 Theory Reference:** See CONCEPTS.md - Sections 6 (Sigstore) & 7 (Verification & Transparency)

---

# Exercise 3.1: Build and Push Container Image

**Build, tag for ttl.sh, and push:**
```bash
# Build container image
task build-image

# Tag for ttl.sh (ephemeral registry, 1-hour TTL)
docker tag supply-chain-app:latest ttl.sh/supply-chain-app-$(hostname):3h

# Push and capture digest
docker push ttl.sh/supply-chain-app-$(hostname):3h 2>&1 | tee /tmp/push-output.txt
```

---

# Exercise 3.1: Extract Digest

**Extract digest and set variables:**
```bash
# Automated extraction
export DIGEST=$(grep "digest:" /tmp/push-output.txt | awk '{print $3}')
export IMAGE=ttl.sh/supply-chain-app-$(hostname)@$DIGEST

# Verify it worked
echo "Image: $IMAGE"
```

**Why digest not tag?** ttl.sh uses tags for TTL (`:3h`), Cosign requires digest references.

**Checkpoint:** `echo $IMAGE` shows `ttl.sh/supply-chain-app-yourname@sha256:...`

---

# Exercise 3.2: Sign the Container Image

**Goal:** Sign the image with your identity

**Command:**
```bash
task exec -- cosign sign --yes $IMAGE
```

**What Happens:**
1. Cosign detects non-interactive mode and uses device flow
2. Terminal displays: verification code and URL
3. You open the URL in your browser and enter the code
4. You authenticate with your email (GitHub/Google)
5. Fulcio issues certificate with your identity
6. Cosign signs the image digest
7. Signature + certificate uploaded to Rekor

---

# Exercise 3.2: Sign Output

**Expected Output:**
```
Non-interactive mode detected, using device flow.
Enter the verification code RKVJ-SBPM in your browser at: https://oauth2.sigstore.dev/auth/device?user_code=RKVJ-SBPM
Code will be valid for 300 seconds
```

**Note:** `--yes` uploads to Rekor. Certificate expires in 10 min, but Rekor preserves it.

**📖 Theory Reference:** CONCEPTS.md - Section 6 (Sigstore architecture & keyless signing)

---

# Exercise 3.3: Inspect the Image Signature

**Goal:** Explore what was created, find your identity

**Step 1 - View artifact tree:**
```bash
task exec -- cosign tree --experimental-oci11 $IMAGE
```

**Output shows:**
```
📦 Supply Chain Security Related artifacts for an image: ttl.sh/...
└── 🔗 application/vnd.oci.empty.v1+json artifacts via OCI referrer: ttl.sh/...
   └── 🍒 sha256:def456... (signature artifact)
```

**You now have:** 1 signature artifact attached to image!

**Note:** The `--experimental-oci11` flag reads artifacts stored in OCI 1.1 referrers format (used by ttl.sh).

---

# Understanding OCI 1.1 and Cosign Flags

**What is OCI 1.1?**
- OCI 1.1 spec introduces native support for artifact references (referrers API)
- Cosign v3 uses OCI 1.1 by default when **writing** artifacts (sign/attest)
- Read operations require `--experimental-oci11` flag in cosign v3
- This will be the only mode in cosign v4 (flag will be default)

**Note:** Some older cosign commands (like `cosign download attestation`) don't support OCI 1.1 mode. Use `cosign verify-attestation` instead, which retrieves and verifies the full attestation.

---

# Exercise 3.3: Verify and Extract Identity

**Step 2 - Verify signature and extract identity:**
```bash
task exec -- cosign verify --experimental-oci11 \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  $IMAGE | jq
```

---

# Exercise 3.3: Verify Output

**Output (simplified):**
```json
[{
  "critical": {
    "identity": {
      "docker-reference": "ttl.sh/supply-chain-app-yourname@sha256:abc..."
    },
    "image": {
      "docker-manifest-digest": "sha256:abc..."
    },
    "type": "https://sigstore.dev/cosign/sign/v1"
  },
  "optional": null
}]
```

**Contains:**
- Image identity: What was signed (digest reference)
- Type: Signature type (cosign sign)
- Verified via: Rekor transparency log

---

# Exercise 3.3: Examine Certificate

**Step 3 - Extract certificate details from Rekor:**
```bash
HASH=$(echo $DIGEST | cut -d: -f2)
UUID=$(task exec -- rekor-cli search --sha $HASH | head -1)

# Download and print rekor record 
task exec -- rekor-cli get --uuid $UUID --format json | jq --color-output | tee /tmp/rekor.json

# Extract short-living certificate issued by fulcio
cat /tmp/rekor.json | jq -r '.Body.DSSEObj.signatures[0].verifier' | base64 -d | openssl x509 -text -noout | grep --color=always -E 'Issuer|Subject Alternative Name|Before|After|email|github|$'
```

**Output shows your identity:**
```
      X509v3 Authority Key Identifier:
          DF:D3:E9:CF:56:24:11:96:F9:A8:D8:E9:28:55:A2:C6:2E:18:64:3F
      X509v3 Subject Alternative Name: critical
          email:nestorandres.rodriguez@thi.de
      1.3.6.1.4.1.57264.1.1:
          https://github.com/login/oauth
      1.3.6.1.4.1.57264.1.8:
          ..https://github.com/login/oauth
```

---

# Exercise 3.3: Certificate Details

**Look for in output:**
- `"email"` - Your email address
- `"1.3.6.1.4.1.57264.1.1"` - OIDC provider URL - Issuer extension from Fulcio
- `"notBefore"` / `"notAfter"` - Certificate validity (10 min!)

**Key Insight:** Your identity is now **permanently bound** to this image!

---

# Exercise 3.4: Sign Provenance Attestation

**Goal:** Sign attestation (different from image signature!)

**Command:**
```bash
task exec -- cosign attest --yes \
  --type slsaprovenance \
  --predicate attestations/provenance.json \
  $IMAGE
```

---

# Exercise 3.4: Explore Provenance Attestation

**Step 1 - See updated tree:**
```bash
task exec -- cosign tree --experimental-oci11 $IMAGE
```

**Output now shows:**
```
📦 Supply Chain Security Related artifacts for an image: ttl.sh/...
├── 🔗 application/vnd.oci.empty.v1+json (signature artifact)
│   └── 🍒 sha256:def456...
└── 🔗 application/vnd.oci.empty.v1+json (provenance attestation)
    └── 🍒 sha256:attestation1...
```

---

# Exercise 3.4: View Attestation

**Step 2 - View and Verify attestation:**
```bash
# Download attestation file
task exec -- cosign verify-attestation --experimental-oci11 \
  --type slsaprovenance \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  $IMAGE | jq | tee /tmp/provenance-attestation.json

# extract uploaded signed payload
cat /tmp/provenance-attestation.json | jq -r '.payload' | base64 -d | jq
```

**Note:** In OCI 1.1 mode, `cosign verify-attestation` retrieves and verifies the full attestation envelope.

**📖 Theory Reference:** CONCEPTS.md - Section 5 (in-toto envelope structure)

---

# Exercise 3.5: Attach Remaining Attestations

**Goal:** Sign SBOM and vulnerability attestations

**Command 1 - SBOM:**
```bash
task exec -- cosign attest --yes \
  --type spdxjson \
  --predicate attestations/sbom.json \
  $IMAGE
```

**Command 2 - Vulnerability (source):**
```bash
task exec -- cosign attest --yes \
  --type vuln \
  --predicate attestations/vuln-source.json \
  $IMAGE
```

---

# Exercise 3.5: Remaining Attestations

**Command 3 - Vulnerability (IaC):**
```bash
task exec -- cosign attest --yes \
  --type vuln \
  --predicate attestations/vuln-iac.json \
  $IMAGE
```

**Command 4 - Vulnerability (image):**
```bash
task exec -- cosign attest --yes \
  --type vuln \
  --predicate attestations/vuln-image.json \
  $IMAGE
```

**Note:** Each command creates a separate attestation artifact with its own signature!

---

# Exercise 3.5: View Complete Artifact Tree

**See all artifacts:**
```bash
task exec -- cosign tree --experimental-oci11 $IMAGE
```

**Output:**
```
📦 Supply Chain Security Related artifacts for an image: ttl.sh/...
├── 🔗 application/vnd.oci.empty.v1+json (image signature)
│   └── 🍒 sha256:...
├── 🔗 application/vnd.oci.empty.v1+json (slsaprovenance attestation)
│   └── 🍒 sha256:...
├── 🔗 application/vnd.oci.empty.v1+json (spdx SBOM attestation)
│   └── 🍒 sha256:...
├── 🔗 application/vnd.oci.empty.v1+json (vuln attestation - source)
│   └── 🍒 sha256:...
├── 🔗 application/vnd.oci.empty.v1+json (vuln attestation - iac)
│   └── 🍒 sha256:...
└── 🔗 application/vnd.oci.empty.v1+json (vuln attestation - image)
    └── 🍒 sha256:...
```

**Total:** 6 artifacts (1 image signature + 5 attestations)

---

# Exercise 3.5: Optional Exploration

**View SBOM attestation:**
```bash
task exec -- cosign verify-attestation --experimental-oci11 \
  --type spdxjson \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  $IMAGE | jq
```

**View vulnerability attestation:**
```bash
task exec -- cosign verify-attestation --experimental-oci11 \
  --type vuln \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  $IMAGE | jq 
```

**Note:** The `--type` parameter filters to specific attestation types. Multiple `vuln` attestations will all be returned.

---

# Exercise 3.6: Verify in Rekor Transparency Log

**Goal:** Explore the permanent audit trail

**📖 Theory Reference:** CONCEPTS.md - Section 7 (Transparency logs & verification)

---

# Exercise 3.6: Search Rekor

**Command 1 - Search by digest:**
```bash
# Extract hash from IMAGE
HASH=$(echo $IMAGE | cut -d@ -f2 | cut -d: -f2)
task exec -- rekor-cli search --sha $HASH
```

**Output:**
```
Found matching entries (listed by UUID):
abc123...
def456...
ghi789...
...
```

**Expected:** 6 entries

---

# Exercise 3.6: Inspect Rekor Entry

**Get details of one entry:**
```bash
# Get first UUID from search results
UUID=$(task exec -- rekor-cli search --sha $HASH | head -1)
task exec -- rekor-cli get --uuid $UUID
```

**Output shows:**
- Log index (position in log)
- Entry UUID (unique identifier)
- Timestamp (when signed)
- Certificate (your identity!)
- Signature
- Artifact digest

**Key Information:** Even after your certificate expires (10 min), Rekor has permanent record!

---

# Phase 3 Summary

**What You Achieved:**
- ✅ Signed container image + 5 attestations
- ✅ All logged in Rekor (6 entries)
- ✅ Keyless signing with OIDC authentication
- ✅ Explored signed artifacts and transparency logs

**📖 Theory Reference:** CONCEPTS.md - Section 4 (SLSA levels)

---

# Validation

**Verify Phase 3 completion:**
```bash
# Set variables if needed
export DIGEST=sha256:abc123...
export IMAGE=ttl.sh/supply-chain-app-$(hostname)@$DIGEST

# Run validation
task validate:phase3
```

**Expected:**
- ✅ DIGEST variable set
- ✅ Image signature verified
- ✅ Attestations verified
- ✅ 6+ Rekor entries found

---

# Future Topics

**Verification & Policy Enforcement**

- Automation over CI/CD Pipeline in Github
- Policy-based verification (only accept images from trusted identities)
- Admission control for Kubernetes

**Preview Question:** "Now that everything is signed, how do we enforce policies like 'only deploy images signed by our team'?"

---

# Resources

**Documentation:**
- Sigstore: https://sigstore.dev
- Cosign: https://docs.sigstore.dev/cosign/overview
- Fulcio: https://docs.sigstore.dev/fulcio/overview
- Rekor: https://docs.sigstore.dev/rekor/overview

**Concepts:**
- See `CONCEPTS.md` for detailed explanations
- SLSA Framework: https://slsa.dev

**Help:**
- Stuck? Review error messages carefully
- Check DIGEST and IMAGE variables are set
- Verify Phase 2 attestation files exist

---
marp: true
theme: default
paginate: true
header: 'Supply Chain Security Lab'
footer: 'Phase 2: Attestations & Provenance'
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

# Phase 2: Attestations & Provenance

**Learning Goals:**
- Generate SLSA provenance attestations
- Create SBOM attestations in in-toto format
- Generate vulnerability attestations
- Understand attestation structure

---

# Prerequisites

- Phase 1 completed
- All vulnerabilities fixed
- Docker image built

**Install docker-container driver for SBOM and Provenance generation**

```bash
docker buildx create --name container-builder --driver docker-container --use
docker buildx inspect --bootstrap
```

**📖 Theory Reference:** See CONCEPTS.md - Sections 4 (SLSA) & 5 (in-toto Attestations)

---

# Exercise 2.1: Generate SLSA Provenance

**Generate Provenance:**
```bash
# Build image with attestation artifacts in out/ folder
task build-image-with-attestation

# Create destination folder for attestations
mkdir -p attestations

# Extract provenance report
cat out/provenance.json | jq .predicate | tee attestations/provenance.json
```

**What It Captures:** Builder identity, Git commit SHA, build timestamps, materials

---

# Exercise 2.1: Inspect Provenance

```bash
jq '__json_path__' attestations/provenance.json
```

| Question / Meaning              | `__json_path__`                                                            |
|---------------------------------|----------------------------------------------------------------------------|
| **Who built it?**              | `.builder.id`                                                             |
| **What build system/type?**    | `.buildType`                                                              |
| **With what inputs (materials)?** | `.materials[]`                                                          |
| **How was it invoked (params)?** | `.invocation.parameters`                                                |
| **Where are build instructions from?** | `.invocation.configSource`                                        |
| **How exactly was it built (steps)?** | `.buildConfig.llbDefinition[]`                                     |
| **When was it built?**         | `.metadata.buildStartedOn`, `.metadata.buildFinishedOn`                   |
| **Is it complete / reproducible?** | `.metadata.completeness`, `.metadata.reproducible`                  |
| **Git repo & commit (VCS info)** | `.metadata."https://mobyproject.org/buildkit@v1#metadata".vcs`                 |

---

# Exercise 2.1: Validate Provenance

**Run Validation:**
```bash
task validate:provenance
```

**What It Checks:**
- ✅ Valid JSON syntax
- ✅ Correct in-toto Statement structure
- ✅ PredicateType = `https://slsa.dev/provenance/v0.2`

---

# Exercise 2.2: Extract SBOM Attestations

```bash
# Extract to destination directory (required for later!)
jq '.predicate' out/sbom.spdx.json > attestations/sbom.json

# View SBOM structure (too large to view entirely)
jq 'keys' attestations/sbom.json

# Check SPDX version
jq '.spdxVersion' attestations/sbom.json

# Count packages
jq '.packages | length' attestations/sbom.json

# Inspect some packages
jq '.packages[5:20] | .[] | {name, versionInfo}' attestations/sbom.json
```

**Note:** Large file (~2MB) with all package details. Syft generates SPDX format, wrapped in in-toto Statement.
**Expected:** ~100+ packages (Python, system libs, dependencies)

---

# Exercise 2.2: Validate SBOM

**Run Validation:**
```bash
task validate:sbom
```

**What It Checks:**
- ✅ Valid JSON syntax
- ✅ Correct in-toto Statement structure
- ✅ PredicateType = `https://spdx.dev/Document`
- ✅ Valid SPDX document with packages
- ✅ Subject matches image name

**Expected Output:**
```
✅ SBOM attestation is valid
   SPDX Version: SPDX-2.3
   Packages: 124
   Subject: supply-chain-app:latest
```

---

# Exercise 2.3: Generate Vulnerability Attestations

**Three Scan Targets:**
- **Source code & dependencies** - Python vulns
- **IaC (Terraform)** - Misconfigurations
- **Container image** - OS & app vulns

**Tool:** Trivy with `--format cosign-vuln` (outputs in-toto Statement format)

*📖 For vulnerability scanning concepts, see CONCEPTS.md Section 3*

---

# Exercise 2.3: Commands

```bash

# Export dependencies scan report from source code to in-toto format 
task exec -- trivy fs --format cosign-vuln src/ > attestations/vuln-source.json

# Export vulnerabilities in IaC artifacts
task exec -- trivy config --format cosign-vuln src/iac/ > attestations/vuln-iac.json

# Export dependencies scan report from source code to in-toto format 
task exec -- trivy image --format cosign-vuln supply-chain-app:latest> attestations/vuln-image.json

```

**Note:** `task exec -- $command $arg1 $arg2 ... $argn` executes the command inside the build-&-tools container

---

# Exercise 2.3: Review All Vulnerability Attestations

**List All Vulnerability Attestations:**
```bash
ls -lh attestations/vuln-*.json
```

**Inspect Attestation Structure:**
```bash

# Explore structure
jq 'keys' attestations/vuln-source.json

# View scanner information
jq '.scanner' attestations/vuln-source.json

# View scan metadata
jq '.metadata' attestations/vuln-source.json

# explore vulnerabilities
jq '.scanner.result.Results[].Vulnerabilities // []' attestations/vuln-image.json
jq '.scanner.result.Results[].Vulnerabilities // []' attestations/vuln-iac.json # None
```

*📖 Note: Trivy's `--format cosign-vuln` outputs standard in-toto Statement + CosignVulnerabilityReport predicate, compatible with Sigstore/Cosign toolchain.*

---

# Exercise 2.4: Review All Attestations

**List Everything You've Generated:**
```bash
ls -lh attestations/
```

**You Should Have:**
- `provenance.json` - Build provenance (SLSA)
- `sbom.json` - Software Bill of Materials (SPDX)
- `vuln-source.json` - Source code scan results
- `vuln-iac.json` - Infrastructure scan results
- `vuln-image.json` - Container image scan results

---

# Exercise 2.4: Validation Output

```bash
task validate:all-attestations
```

**Expected Output:**
```
✅ SLSA provenance attestation is valid
✅ SBOM attestation is valid
✅ Source vulnerability attestation is valid
✅ Iac vulnerability attestation is valid
✅ Image vulnerability attestation is valid
All attestations validated successfully!
```

*📖 For attestation structure details, see CONCEPTS.md Section 5: in-toto Attestations*

---

# Phase 2 Summary

**What You Accomplished:**
- Generated SLSA provenance (build metadata)
- Created SBOM attestation (component inventory)
- Generated 3 vulnerability attestations (scan results)
- Validated all attestation structures
- Understood in-toto Statement format

**Why This Matters:** Attestations provide verifiable proof for CI/CD gates, compliance, supply chain attack detection, and license compliance.

*📖 See CONCEPTS.md Sections 4 & 5*

---

# Checkpoint

**Before proceeding to Phase 3, verify:**
- [ ] All 5 attestations generated in `attestations/`
- [ ] `task validate:all-attestations` passes
- [ ] You understand in-toto Statement structure
- [ ] You can explain what each attestation type contains

**Ready?** Move to Phase 3: Signing with Keyless Authentication

---

<!-- Overview -->
## What This Covers

![bg left:20%](./img/aurora.png)

Node autoscaling on Aurora: evaluating Karpenter as a reference implementation and Azure evaluation

- **Karpenter** - cloud-agnostic just-in-time node provisioning
- **AKS Node Auto Provisioning (NAP)** - Azure's managed Karpenter offering
- **Cluster Autoscaler** - current baseline, remains production

<blockquote>
We need Karpenter expertise regardless of the final choice per cloud. Build a reference, test Azure options.
</blockquote>

---

<!-- The proposal -->
## Aurora Karpenter Learning and Azure Evaluation Proposal

![bg left:20%](./img/aurora.png)

**Goal:** Build Karpenter as Aurora's cross-platform reference, starting with Azure evaluation

**Two outputs:**
1. Platform-independent reference and method: NodePool design, disruption, observability, runbooks
2. Evidence-based Azure recommendation: remain on Cluster Autoscaler, adopt AKS NAP, or self-hosted Karpenter

**What this covers:**
- Karpenter concepts, APIs, operational behavior, failure modes
- Self-hosted Karpenter reference on Azure
- AKS NAP pilot
- Three-way comparison against Cluster Autoscaler baseline

**What this does NOT decide:**
- Single autoscaler for AWS, Azure, GKE, on-prem
- Production migration
- Cost savings (baseline measurements needed first)

---

<!-- Platform status -->
## Platform Status

| Platform | Status Today | In Scope | Next Step |
|----------|--------------|----------|-----------|
| **Azure (AKS)** | In production; Cluster Autoscaler | Self-hosted reference + AKS NAP pilot | Decision by [date] |
| **AWS** | Supported in platform chart; no clusters | Separate option | Evaluate by [date] |
| **GKE** | Architectural direction | Separate decision | Risk assessment by [date] |
| **On-prem** | Architectural direction | Self-hosted most important | Revisit by [date] |

**Why Azure first:**
- Aurora's production platform today
- Managed Karpenter option exists (NAP)
- First-party self-hosted provider available

> **Terminology note:** AKS NAP (Azure) and GKE NAP are NOT the same thing. This document uses prefixed names.

---

<!-- Recommendation -->
## Recommendation

### 0. Check eligibility first

Before building anything, confirm Aurora's AKS clusters can use AKS NAP:
- Managed Cilium CNI compatibility
- Feature requirements
- Incompatibility with Cluster Autoscaler on same cluster

If NAP is not viable, the pilot narrows to self-hosted Karpenter vs Cluster Autoscaler.

### 1. Build self-hosted Azure reference

Deploy self-hosted Karpenter on a separate non-production AKS cluster to learn:
- NodePool and NodeClass definitions
- Workload constraints, limits, capacity types, disruption policies
- Provisioning, consolidation, replacement, failure behavior
- Metrics, logs, alerts, cost reporting
- Identity, quotas, upgrades, rollback, emergency capacity

### 2. Pilot AKS NAP

Pilot AKS NAP on a separate non-production cluster. NAP is Microsoft-managed and Karpenter-based but Microsoft controls the managed components, release schedule, lifecycle operations.

### 3. Compare three options

Compare **Cluster Autoscaler (baseline)**, **self-hosted Karpenter**, and **AKS NAP** using identical workload profiles. Never run two autoscalers against the same cluster.

### 4. Make an evidence-based Azure decision

- **Adopt AKS NAP** if it meets criteria and managed trade-offs acceptable
- **Adopt self-hosted Karpenter** if NAP has gaps and Karpenter meets criteria
- **Remain on Cluster Autoscaler** if neither demonstrates sufficient benefit

---

<!-- What transfers -->
## What Transfers Across Platforms

| Transfers | Does Not Transfer |
|-----------|-------------------|
| NodePool constraints, limits, capacity-type logic | NodeClass definitions (provider-specific) |
| Disruption budgets, consolidation, drift behavior | Node images, boot path, image-patching mechanics |
| Interaction with PDBs, VPA, KEDA, scale-to-zero | Cloud identity, permissions, quota management |
| Metrics, alerting, troubleshooting approach | Instance/SKU availability and regional constraints |
| Evaluation method and acceptance criteria | Managed-service support boundaries and release cadence |

**Key insight:** Azure results do not transfer to other platforms. Each cloud needs its own evaluation.

---

<!-- How it works -->
## How Node Autoscaling Works: Complete Picture

![bg left:20%](./img/aurora.png)

1. **Workload** - pods with resource requests, PDBs, constraints
2. **Scheduler** - cannot place pending pods due to capacity
3. **Autoscaler** (CA or Karpenter)
   - CA: adds one node to pre-defined pool
   - Karpenter: provisions single node that fits the pod
4. **Node** boots, pulls images, becomes ready
5. **Pod** schedules on the new node

**Important:** Node-startup time (image pull, boot) is separate from autoscaler provisioning. Switching controllers does not create warm capacity or remove image-pull latency.

---

<!-- Karpenter vs Cluster Autoscaler -->
## Why Karpenter Over Cluster Autoscaler

| Aspect | Cluster Autoscaler | Karpenter |
|--------|-------------------|-----------|
| Node provisioning | Adds nodes one at a time to a node group | Provisions single node that fits each pending pod |
| Instance selection | Uses expanders (least-waste, price, priority) | Chooses cheapest instance type that fits |
| Consolidation | Removes underutilized nodes after draining | Continuous repacking and node removal |
| Multi-family | Static pool per node group | Any family, spot + on-demand mixed |
| Provisioning speed | Minutes | ~45-60s (vendor benchmark) |

> **Estimated 20-40% cost reduction vs Cluster Autoscaler** ([AWS case study](https://repost.aws/articles/AR5C03QTEyRgKoDI-XO5UC7w/optimizing-your-amazon-eks-compute-costs-with-karpenter)) - validate in Aurora pilot.

---

<!-- NodePool -->
## Karpenter: NodePool as Source of Truth

![bg left:20%](./img/aurora.png)

Define compute intent once; tailor the provider-specific `nodeClassRef` per platform (EC2NodeClass, AKSNodeClass, GKENodeClass, etc).

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        name: default
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30m
  limits:
    cpu: "1000"
```

**Key concepts:**
- `NodePool` - Aurora's source of truth for node autoscaling
- `NodeClass` - provider-specific (EC2NodeClass, AKSNodeClass, etc)
- `limits` - prevent runaway provisioning
- `consolidateAfter` - tune to workload churn tolerance

---

<!-- Why self-hosted -->
## Why Self-Hosted Karpenter When Possible

**Goal:** Build in-house Karpenter expertise to use across clouds

- **AWS:** Self-hosted Karpenter (v1 GA, full control)
- **Azure:** Try AKS NAP (managed); switch to self-hosted if constraints appear
- **GKE:** Self-hosted Karpenter (via CloudPilot AI shim)
- **On-prem:** Self-hosted Karpenter (you own infrastructure)

**Why self-hosted:**
- Same NodePool APIs across all platforms
- Full version control and security scanning
- Avoids vendor cost manipulation
- Freedom to migrate if CSP solution doesn't meet Aurora's goals

**Azure NAP trade-off:** Managed simplicity now, but vendor lock-in risk later.

---

<!-- Risks -->
## Karpenter: Risks and Caveats

| Platform | Risk | Mitigation |
|----------|------|------------|
| **GCP** | Provider is community-maintained (pre-1.0) | Pin versions, scan, keep GKE Workload Autoscaler as fallback |
| **All** | Node churn from aggressive consolidation | Tune `consolidateAfter`, use PodDisruptionBudgets |
| **Azure** | NAP vendor lock-in risk | Include observability, troubleshooting, exit testing in criteria |
| **All** | Model change is cluster-creation-time decision | Learn Karpenter first, choose CSP NAP only if it works |

> Learn Karpenter. Use CSP NAP if it works. Switch back to self-hosted if constraints emerge.

---

<!-- Evaluation design -->
## Evaluation Design

### Baseline (Cluster Autoscaler)

Record current behavior:
- Pod pending-to-scheduled latency
- Node provisioning and readiness latency
- Image-pull time after node readiness
- Node utilization and requested capacity
- Scale-down and disruption behavior
- Infrastructure cost per test window
- Failure, quota, and scheduling events

### Test Cases

1. Stateless service with predictable demand
2. Bursty workload creating pending pods
3. Workload with strict taints, tolerations, affinity
4. Workload protected by PDB
5. Workload with large images or slow startup hooks
6. Workload exercising scale-down and consolidation
7. **KEDA-scaled workload** (scale-to-zero, scale-up from zero)
8. **VPA-managed workload** (requests change after scheduling)
9. **Zonal storage** (PV with zone affinity, DaemonSet overhead)
10. **Node lifecycle events** (image patching, drift, expiry)

KEDA and VPA are planned Aurora capabilities; include them so evaluation covers target state.

---

<!-- Acceptance criteria -->
## Acceptance Criteria

Thresholds must be set **before testing begins**:

| Area | Evidence Required | Threshold |
|------|-------------------|-----------|
| Provisioning | Nodes become available for all constraints | [>= 99% success] |
| Latency | Pending-to-ready under load | [p95 <= X seconds] |
| Consolidation | No PDB violations across N events | [zero violations] |
| Configuration | Labels, taints, images, zones, SKUs supported | [all required] |
| Observability | Metrics, alerts, logs support diagnosis | [all alerts fire] |
| Operations | Upgrades, rollback, incident procedures tested | [each executed] |
| Security | PBMM review per option | [per Aurora security review] |

**Security differs by option:**
- Self-hosted: least-privilege controller identity and node permissions
- AKS NAP: audit Microsoft's managed controller permissions and data handling

---

<!-- Timeline -->
## Timeline, Effort, and Ownership

| Item | Value |
|------|-------|
| Total duration | [e.g., 10-12 weeks, time-boxed] |
| Team and allocation | [names/roles, % allocation] |
| Estimated infrastructure cost | [non-production cluster cost] |
| Decision date | [date] |

---

<!-- Startup behavior -->
## Startup Versus Autoscaler Behavior

The pilot must separate autoscaler behavior from node-startup behavior:

- **Provisioning latency** - controller sees pending pod to node being created
- **Node startup latency** - node boots, pulls images, becomes ready
- **Scheduling latency** - pod scheduled on ready node

Switching controllers does not create warm capacity or remove image-pull latency. Treat startup time as a **measured variable per option**, not an assumption.

If Aurora requires warm headroom, evaluate separately: static warm pool, low-priority overprovisioning pods, image pre-pulling, or explicit minimum capacity.

---

<!-- Expected deliverables -->
## Expected Deliverables

- Version-controlled self-hosted Karpenter reference configuration (Aurora's source of truth)
- AKS NAP pilot configuration and operating notes
- Baseline and three-way comparison measurements
- Dashboards, alerts, and troubleshooting runbooks
- Documented upgrade, rollback, image-patching, and exit procedures
- Reusable evaluation method for other platforms
- Azure recommendation supported by pilot evidence

---

<!-- Conclusion -->
## Conclusion

Aurora needs a Karpenter reference it owns because:

- Karpenter-based options are emerging across Azure, AWS, and elsewhere
- On-prem will have no managed alternative

A time-boxed Azure evaluation:
- Builds Aurora's Karpenter reference
- Produces reusable method
- Gives Azure an evidence-based answer

Aurora stays adaptable: where a cloud offers managed Karpenter (like Azure NAP), it is worth trying precisely because the team will understand what sits underneath.

The result may be:
- **AKS NAP** - managed Karpenter, pragmatic default
- **Self-hosted Karpenter** - full control, cross-platform reference
- **Remain on Cluster Autoscaler** - if neither shows sufficient benefit

In each case, Aurora will understand why.

---

<!-- References -->
## References

### Upstream:
1. <a href="https://karpenter.sh/docs/">Karpenter documentation</a>
2. <a href="https://karpenter.sh/docs/concepts/">Karpenter concepts</a>
3. <a href="https://github.com/kubernetes-sigs/karpenter">Karpenter upstream</a>
4. <a href="https://github.com/Azure/karpenter-provider-azure">Azure Karpenter provider</a>

### Azure:
5. <a href="https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning">AKS Node Auto Provisioning</a>
6. <a href="https://docs.aws.amazon.com/eks/latest/best-practices/automode.html">AWS EKS Auto Mode</a>
7. <a href="https://cloud.google.com/kubernetes-engine/docs/concepts/node-auto-provisioning">GKE Node Auto-Provisioning</a>

### Aurora Platform:
8. <a href="https://github.com/gccloudone-aurora/aurora-platform-charts">Aurora Platform Charts</a>

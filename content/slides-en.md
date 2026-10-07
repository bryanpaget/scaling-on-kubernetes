---

<!-- Overview -->
## What This Covers

![bg left:20%](./img/aurora.png)

Three autoscalers Aurora runs, and how they fit together:

- **VPA** - right-sizes pod CPU/memory requests
- **KEDA** - event- and schedule-driven replica scaling (including scale-to-zero)
- **Karpenter** - just-in-time node provisioning and consolidation

<blockquote>
Different tools, different axes. The value is in how they combine.
</blockquote>

---

<!-- Scaling axes map -->
## The Scaling Stack: Three Axes, Four Tools

![bg left:20%](./img/aurora.png)

| Axis | Tool(s) | Scales | Level | Trigger |
|------|---------|--------|-------|---------|
| **Pod replica count** | HPA, KEDA | Replicas | Pod | Metrics (HPA) or events/schedule (KEDA) |
| **Pod resource size** | VPA | CPU/memory requests+limits | Pod | Usage history |
| **Node capacity** | Karpenter | Nodes | Infrastructure | Pending pods |

---

<!-- How they layer -->
## How They Layer

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">HPA / KEDA</div>
    <div class="plate">Decide replica count</div>
    <div class="plate">(how many pods)</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">VPA</div>
    <div class="plate">Sets each pod's</div>
    <div class="plate">CPU / memory</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Karpenter</div>
    <div class="plate">Provisions nodes</div>
    <div class="plate">to fit the pods</div>
  </div>
</div>

<blockquote>
Replica count x per-pod size = pending-pod demand that Karpenter satisfies.
</blockquote>

---

<!-- ============================ PART 1: VPA ============================ -->
<!-- VPA section divider -->
# Part 1: VPA
## Right-sizing pod resources

![bg left:30%](./img/aurora.png)

---

<!-- What is VPA? -->
## What is VPA?

**Vertical Pod Autoscaler:** automatically adjusts CPU and memory resource *requests and limits* for your containers

![bg left:20%](./img/aurora.png)

- Unlike HPA which scales *replicas*, VPA scales *resource requests/limits*
- Works with Deployments, StatefulSets, DaemonSets
- Consists of three components: Recommender, Updater, and Admission Controller
- Kubernetes-native via Custom Resource Definitions
- By default scales both requests and limits proportionally; use `controlledValues: RequestsOnly` to scale requests only

<blockquote>
HPA scales how many, VPA scales how much.
</blockquote>

---

<!-- Why VPA Matters -->
## Why VPA Matters

![bg left:20%](./img/aurora.png)

### The Resource Request Problem:
- Over-provisioning: 500m CPU when 100m needed, wasted capacity
- Under-provisioning: 100m CPU when 500m needed, throttling
- Static requests never adjust after deployment

### VPA Solves This:
- **Right-sizing at pod creation:** Initial mode applies recommendations only to new pods
- **Continuous monitoring:** Recommender analyzes usage over time
- **Controlled updates:** Updater can gradually roll out changes via InPlace updates (where available)

<blockquote>
Stop guessing, start sizing with data.
</blockquote>

---

<!-- How VPA Works -->
## How VPA Works: Three Components

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">Recommender</div>
    <div class="plate">Analyzes usage patterns</div>
    <div class="plate">Calculates recommendations</div>
    <div class="plate">Runs continuously</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Updater</div>
    <div class="plate">Checks recommendations</div>
    <div class="plate">Decides when to update</div>
    <div class="plate">Respects PDB/rollout</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Admission Controller</div>
    <div class="plate">Intercepts pod requests</div>
    <div class="plate">Applies recommendations</div>
    <div class="plate">Ensures right-sized resources</div>
  </div>
</div>

---

<!-- VPA Modes -->
## VPA Modes: Choose Your Risk Profile

![bg left:20%](./img/aurora.png)

| Mode | Updates Existing Pods | Evicts Pods | Production Use |
|------|----------------------|-------------|----------------|
| **Off** | No | No | Analysis only |
| **Initial** | No | No | Recommended for prod |
| **InPlace** | Yes (in-place, no eviction) | No* | Recommended for prod |
| **InPlaceOrRecreate** | Yes (in-place first, then recreate) | Yes (if InPlace fails) | Balanced, dev/test |
| **Recreate** | Yes (only via eviction) | Yes | Use rarely |
| **Auto** | Deprecated | Deprecated | Do not use |

* Requires `InPlacePodVerticalScaling` feature gate and a Kubernetes version that supports it. Falls back to Recreate if unavailable.

---

<!-- Aurora VPA defaults -->
## VPA on Aurora: Platform Defaults

![bg left:20%](./img/aurora.png)

| Setting | Value |
|---------|-------|
| VPA Version | 1.7 (latest; appVersion 1.35+) |
| Namespace | vpa-system |
| Metrics Server | Enabled (required) |
| Admission Controller | Enabled (mutating webhook) |
| Prometheus/ServiceMonitor | Disabled (opt-in per workload) |

**Deployment:** via the aurora-core chart. Platform-level enablement is already done.

---

<!-- VPA example -->
## VPA Example

![bg left:20%](./img/aurora.png)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: "Initial"   # or "InPlace"
  resourcePolicy:
    containerPolicies:
      - containerName: "*"
        minAllowed: { cpu: 50m, memory: 64Mi }
        maxAllowed: { cpu: 500m, memory: 512Mi }
        controlledValues: "RequestsAndLimits"  # or "RequestsOnly"
        controlledResources: ["cpu", "memory"]
```

**Bounds matter:** `minAllowed` prevents under-sizing (keeps pods schedulable); `maxAllowed` prevents over-sizing recommendations. Scales both requests and limits proportionally by default.

---

<!-- VPA limitations -->
## VPA: When NOT to Use It

![bg left:20%](./img/aurora.png)

- **Spiky workloads:** VPA reacts to history; sudden bursts can be under-provisioned until it catches up
- **JVM / heap-tuned apps:** changing memory requests does not change `-Xmx`; size the runtime, not just the pod
- **Eviction-sensitive workloads:** avoid `Recreate` where restarts are costly
- **Same resource as HPA/KEDA:** never let two controllers fight over the same resource (see Part 4)
- **Very short-lived processes:** VPA needs time to collect and analyze usage data

---

<!-- ============================ PART 2: KEDA ============================ -->
<!-- KEDA section divider -->
# Part 2: KEDA
## Event- and schedule-driven replica scaling

![bg left:30%](./img/aurora.png)

---

<!-- What is KEDA -->
## What is KEDA?

**Kubernetes Event-Driven Autoscaler:** scales replica count based on events, queues, or schedules

![bg left:20%](./img/aurora.png)

- Scales on external signals: Kafka lag, queue depth, cron, custom metrics
- Can **scale to zero** when there is nothing to do
- Drives a standard HPA under the hood (you do not create the HPA yourself)
- Config via `ScaledObject` (long-running) or `ScaledJob` (batch)

<blockquote>
HPA reacts to CPU. KEDA reacts to the thing that actually drives your load.
</blockquote>

---

<!-- KEDA Aurora defaults -->
## KEDA on Aurora: Platform Defaults

![bg left:20%](./img/aurora.png)

| Setting | Value |
|---------|-------|
| KEDA Version | 2.16+ (latest stable) |
| Namespace | keda-system |
| Metrics Server | Enabled (required) |
| Prometheus/ServiceMonitor | Disabled (opt-in per workload) |

**Two ways to use it:**
- **Platform-native off-hours scaling** (recommended): set `offHoursScaling` in the aurora-namespace chart; ScaledObjects are generated for you
- **Manual ScaledObject:** for events, queues, or custom logic

---

<!-- KEDA platform-native -->
## KEDA: Platform-Native Off-Hours Scaling

![bg left:20%](./img/aurora.png)

Recommended for standard business-hours scaling. Disabled by default.

```yaml
offHoursScaling:
  enabled: true
  defaultSchedule:
    start: "0 7 * * 1-5"        # Mon-Fri 7:00
    end: "0 19 * * 1-5"         # Mon-Fri 19:00
    timezone: "America/Toronto"
  minReplicas: 1                # keep 1 outside hours (prod)
  workloads:
    - name: my-api
      businessHoursReplicas: 2
```

The chart generates compliant ScaledObjects, labels, and annotations for you.

---

<!-- KEDA manual -->
## KEDA: Manual ScaledObject

![bg left:20%](./img/aurora.png)

For events, queues, or scale-to-zero (non-prod).

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
spec:
  scaleTargetRef:
    name: my-app-deployment
  minReplicaCount: 0            # scale to zero (non-prod only)
  maxReplicaCount: 5
  cooldownPeriod: 300
  triggers:
    - type: cron
      metadata:
        timezone: America/Toronto
        start: "0 6 * * 1-5"
        end: "0 20 * * 1-5"
        desiredReplicas: "3"
```

---

<!-- KEDA limitations -->
## KEDA: Production Guardrails

![bg left:20%](./img/aurora.png)

### DO NOT:
- **Use KEDA and your own HPA together** - KEDA creates and manages the HPA; you own only the ScaledObject
- **Create your own HPA** for a KEDA-managed workload - KEDA owns it
- **Rely on short cooldowns for isolation** - `cooldownPeriod` (default 300s) only affects the final scale-from-zero, not general scale-down (that is HPA's `behavior` window)

### DO:
- Keep `minReplicaCount: 1`+ in production (no scale-to-zero)
- Add `terminationGracePeriodSeconds` for long-running consumers
- Use `ScaledJob` for event-processing batch work
- Validate across a full 24-hour cycle in non-prod

---

<!-- ============================ PART 3: Karpenter ============================ -->
<!-- Karpenter section divider -->
# Part 3: Karpenter
## Just-in-time node provisioning

![bg left:30%](./img/aurora.png)

---

<!-- What is Karpenter -->
## What is Karpenter?

**Cloud-agnostic node autoscaler:** provisions nodes just-in-time for pending pods, then consolidates

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">Watch</div>
    <div class="plate">Pod the scheduler</div>
    <div class="plate">cannot place</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Provision</div>
    <div class="plate">Cheapest node</div>
    <div class="plate">that fits the pod</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Consolidate</div>
    <div class="plate">Repack workloads</div>
    <div class="plate">Remove idle nodes</div>
  </div>
</div>

<blockquote>
Cluster Autoscaler scales pre-defined pools. Karpenter picks the right node per demand, then tidies up.
</blockquote>

---

<!-- Karpenter why -->
## Why Karpenter over Cluster Autoscaler

![bg left:20%](./img/aurora.png)

| Aspect | Cluster Autoscaler | Karpenter |
|--------|-------------------|-----------|
| Node provisioning | Adds nodes one at a time to a node group | Provisions single node that fits each pending pod |
| Instance selection | Uses expanders (least-waste, price, priority) | Chooses cheapest instance type that fits |
| Consolidation | Removes underutilized nodes after draining | Continuous repacking and node removal |
| Multi-family | Static pool per node group | Any family, spot + on-demand mixed |
| Provisioning speed | Minutes | ~45-60s (vendor benchmark) |

> Estimated 20-40% cost reduction vs Cluster Autoscaler ([AWS case study](https://repost.aws/articles/AR5C03QTEyRgKoDI-XO5UC7w/optimizing-your-amazon-eks-compute-costs-with-karpenter)) - validate in a pilot.

---

<!-- Karpenter NodePool -->
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
        name: default           # points to EC2NodeClass, AKSNodeClass, etc (provider-specific)
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]   # prefer spot
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30m    # tune to workload churn tolerance
  limits:
    cpu: "1000"              # prevent runaway provisioning
```

---

<!-- Karpenter Aurora -->
## Karpenter on Aurora: The Strategy

![bg left:20%](./img/aurora.png)

**Goal:** Build in-house Karpenter expertise to use across clouds, falling back to CSP-managed solutions when they're sufficient.

- **AWS:** Self-hosted Karpenter (v1 GA provider, full control)
- **Azure:** Try AKS NAP (managed Karpenter); switch to self-hosted if constraints appear
- **GKE:** Self-hosted Karpenter (via [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp))
- **On-premises:** Self-hosted Karpenter (you own the infrastructure)

**Why self-hosted when possible:**
- Same NodePool APIs across all platforms
- Full version control and security scanning
- Avoids vendor cost manipulation
- Freedom to migrate if a CSP solution doesn't meet Aurora's goals

**Azure NAP trade-off:** Managed simplicity now, but vendor lock-in risk later.

<blockquote>
Learn Karpenter. Use CSP NAP if it works. Switch back to self-hosted if constraints emerge.
</blockquote>

---

<!-- Karpenter limitations -->
## Karpenter: Risks and Caveats

![bg left:20%](./img/aurora.png)

- **GCP provider is community-maintained:** the [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp) is pre-1.0; breaking changes happen. Pin versions, scan, and keep GKE Workload Autoscaler as fallback
- **Node churn:** aggressive consolidation disrupts pods; tune `consolidateAfter` and use PodDisruptionBudgets
- **Azure NAP trade-off:** simpler now, but harder to switch later if constraints appear (vendor-specific APIs, version lock, cost control)
- **Model change:** autoscaler choice is set at cluster creation time on all platforms
- **Set `limits`** on NodePool to prevent runaway provisioning
- **Learn Karpenter first:** understand the open-source project before choosing a managed variant

---

<!-- ============================ PART 4: Interactions ============================ -->
<!-- Interactions divider -->
# Part 4: Putting It Together
## Interactions and anti-patterns

![bg left:30%](./img/aurora.png)

---

<!-- The combined picture -->
## How It Works: The Complete Picture

![bg left:20%](./img/aurora.png)

1. **KEDA / HPA** decide replica count (driven by events or metrics)
2. **VPA** sizes each pod based on usage history
3. **Combined:** Replica count × per-pod size = total pending-pod demand
4. **Karpenter** watches for unschedulable pods and provisions nodes

<blockquote>
All three feed one pipeline. Keep them off each other's axes and they compound.
</blockquote>

---

<!-- Conflict rules -->
## The Rules That Keep Them From Fighting

![bg left:20%](./img/aurora.png)

| Pair | Rule |
|------|------|
| **VPA + HPA** | Never on the same resource. VPA = memory, HPA = CPU (`controlledResources`) |
| **VPA + KEDA** | Conflict only with CPU/memory triggers. Safe with queue depth, cron, or custom metrics |
| **KEDA + own HPA** | Do not create your own HPA; KEDA owns it (`transfer-hpa-ownership` if needed) |
| **VPA + Karpenter** | Complementary: VPA changes requests, Karpenter repacks. Set VPA `maxAllowed` and NodePool `limits` |
| **KEDA 0 + Karpenter** | Scale-to-zero + consolidation empties and removes nodes. Watch cold-start latency |

---

<!-- Anti-patterns -->
## Anti-Patterns to Avoid

![bg left:20%](./img/aurora.png)

- **VPA and HPA/KEDA on the same metric** - they compete for the same resource and oscillate
- **VPA `Recreate` on eviction-sensitive workloads** - prefer Initial/InPlace
- **Scale-to-zero in production** without planning for cold-start latency
- **No `maxAllowed` on VPA / no `limits` on NodePool** - a runaway recommendation can pin a node
- **Aggressive consolidation without PodDisruptionBudgets** - node churn disrupts workloads; use `consolidateAfter` and PDBs

---

<!-- Conclusion -->
## Conclusion

![bg left:20%](./img/aurora.png)

- **VPA** right-sizes pods (how much)
- **KEDA** scales replicas on real demand, including to zero (how many)
- **Karpenter** provisions and consolidates nodes (what capacity)
- **Together** they form one pipeline: keep them off each other's axes and they compound

<blockquote>
Right-size the pods, scale on real demand, provision only what fits.
</blockquote>

---

<!-- References -->
## References

![bg left:20%](./img/aurora.png)

### Upstream:
1. <a href="https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/README.md">VPA (kubernetes/autoscaler)</a>
2. <a href="https://keda.sh/docs/">KEDA documentation</a>
3. <a href="https://karpenter.sh/">Karpenter documentation</a>

### Aurora Platform:
4. <a href="https://github.com/gccloudone-aurora/aurora-platform-charts">Aurora Platform Charts</a>
5. VPA / KEDA usage guides and the Karpenter autoscaling proposal (docs-main)

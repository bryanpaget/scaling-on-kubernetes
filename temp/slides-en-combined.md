---
marp: true
theme: default
paginate: true
backgroundColor: "#ffffff"
header: "Scaling on Kubernetes - SSC Aurora Platform"
footer: ""
size: "16:9"
style: |
  section { font-size: 26px; }
  h1 { font-size: 36px; }
  h2 { font-size: 30px; }
  h3 { font-size: 24px; }
  h4 { font-size: 22px; }
  blockquote { font-size: 24px; }
  table { font-size: 22px; }
---

![bg left:50%](img/aurora.png)

<br>

# Scaling on Kubernetes
## VPA, KEDA, and Karpenter on the Aurora Platform

<br>

#### Aurora Platform Team 2026

*Workload and node autoscaling: a platform team guide*

---

<!-- Overview -->
## What This Covers

![bg left:20%](./img/aurora.png)

Scaling on Aurora: understanding how autoscalers fit together

- **VPA** - right-sizes pod CPU/memory requests
- **KEDA** - event- and schedule-driven replica scaling (including scale-to-zero)
- **Karpenter** - just-in-time node provisioning and consolidation

<br>

<blockquote>
Different tools, different axes. The value is in how they combine.
</blockquote>

---

<!-- Scaling axes map -->
## The Scaling Stack: Three Axes

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">KEDA</div>
    <div class="plate">Scales replica count</div>
    <div class="plate">Driven by events & queues</div>
    <div class="plate"><i>(How many pods)</i></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">VPA</div>
    <div class="plate">Sizes pod resources</div>
    <div class="plate">Adjusts requests & limits</div>
    <div class="plate"><i>(How big of a pod)</i></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">Karpenter</div>
    <div class="plate">Provisions right-sized nodes</div>
    <div class="plate">Binds pending pods to compute</div>
    <div class="plate"><i>(Where the pods fit)</i></div>
  </div>
</div>

<br>

<blockquote>
Replica count × per-pod size = pending-pod demand that Karpenter satisfies.
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

**Vertical Pod Autoscaler:** automatically adjusts the CPU and memory resource requests and limits of running Kubernetes pods based on real-time usage and predefined boundaries

* **Targets:** Workload CPU/memory requests & limits
* **Workloads:** Deployments, StatefulSets, DaemonSets
* **Architecture:** Recommender, Updater, Admission Controller
* **Native:** Implemented via standard CRDs
* **Config:** Use `controlledValues: RequestsOnly` to protect custom limits

<br>

<blockquote>
HPA scales how many, VPA scales how much.
</blockquote>

---

<!-- Why VPA Matters: Initial Mode Focus -->
## VPA in Production: Day-Zero Right-Sizing

The biggest barrier to resource efficiency is the **Static Baseline Trap**—engineers hardcode generic resource values during deployment and never modify them. 

### Enter `Initial` Mode: Sizing at Pod Creation
Instead of dynamically altering live infrastructure, VPA can act as a **smart template injector** at the exact moment a pod is born.

* **Historical Ingestion:** The Recommender continuously tracks your application's true production footprint in the background.
* **Mutating at Birth:** When a deployment triggers a rollout or a pod restarts, the Admission Controller intercepts the request *before* it schedules.
* **Telemetry over Guesstimates:** VPA strips out the developer's hardcoded numbers and injects an exact, data-driven resource target.
* **Zero Production Churn:** Once the pod is running, VPA locks the settings. It will **never evict or restart** a live container mid-flight.

<br>

<blockquote>
Profiles over predictions. Lock in optimal footprint on day zero, with zero runtime risk.
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
    <div class="plate">Respects Pod Distribution Budgets/rollout</div>
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

<!-- How the Recommender works -->
## How the Recommender Works

![bg left:25%](./img/aurora.png)

The foundational "brain" of VPA. It only **proposes** metrics—it never modifies running pods.

1. **Continuous Monitoring** - Pulls utilization from Metrics Server/Prometheus
2. **Historical Analysis** - Decaying moving average, peaks matter most (no OOMs!)
3. **Target Generation** - Calculates and writes four target zones to VPA Status

---

<!-- In-Place Resizing -->
## In-Place Resizing: Zero-Interruption Right-Sizing

![bg left:25%](./img/aurora.png)

Modifies CPU and memory allocation on the fly without evicting or restarting running pods.

To achieve true zero-interruption scaling, four layers must align:
- **Application Runtime:** Runtimes effortlessly absorb extra CPU, but memory scaling requires dynamic cgroup tracking (e.g., configuring JVM heap bounds)
- **Node Capacity:** The underlying physical node must have immediate headroom (spare capacity) to accommodate a scale-up request
- **Risk Management:** Downscaling requires guardrails; shrinking memory allocation too aggressively will trigger instant Out-Of-Memory (OOM) kills
- **Platform Engine:** Managed automatically by Aurora on Kubernetes 1.27+ via the `InPlacePodVerticalScaling` feature gate

<br>

<blockquote>
Fallback: <b>InPlaceOrRecreate</b> drops back to eviction if node space or runtime compatibility is locked.
</blockquote>

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
- **Same resource as KEDA:** never let two controllers fight over the same resource (see Part 4)
- **Very short-lived processes:** VPA needs time to collect and analyze usage data

> **That's the 'how much' axis.** Next: KEDA decides *how many* replicas you need.

---

<!-- ============================ PART 2: KEDA ============================ -->
<!-- KEDA section divider -->
# Part 2: KEDA
## Event- and schedule-driven replica scaling

![bg left:30%](./img/aurora.png)

---

<!-- What is KEDA -->
## What is KEDA?

**Kubernetes Event-Driven Autoscaler:** scales replica count based on events, queues, or cron schedules

![bg left:20%](./img/aurora.png)

- Scales on external signals: Kafka lag, queue depth, cron schedules, or HTTP traffic
- Acts as a broker: translates external metrics into native HPA targets
- Enables scale-to-zero: safely unloads idle workloads down to 0 replicas
- Config via `ScaledObject` (long-running) or `ScaledJob` (batch)

<br>

<blockquote>
HPA reacts to CPU. KEDA reacts to what actually drives your load.
</blockquote>

---

<!-- How KEDA works -->
## How KEDA Works

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">ScaledObject</div>
    <div class="plate">You define:</div>
    <div class="plate">Events, triggers, scaling rules</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">KEDA Operator</div>
    <div class="plate">Creates & manages:</div>
    <div class="plate">Standard HPA behind the scenes</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">HPA</div>
    <div class="plate">Controls replica count</div>
    <div class="plate">for your deployment</div>
  </div>
</div>

<br>

> **You only configure the ScaledObject.** KEDA owns the HPA and ensures it stays in sync with your event-based scaling rules.

---

<!-- Why KEDA matters -->
## Why KEDA Matters

![bg left:20%](./img/aurora.png)

### The Replica Scaling Problem:
- **HPA on CPU/memory:** Scales too late - by the time CPU is high, it's already too late
- **Static replicas:** Either over-provision (wasted capacity) or under-provision (bad UX)
- **Manual scaling:** Reactive, error-prone, exhausting

### KEDA Solves This:
- **Event-driven scale-up:** Start scaling *before* CPU rises - Kafka lag, queue depth, or Prometheus alerts
- **Scale-to-zero:** When there's nothing to do, run 0 replicas. When traffic arrives, scale to N
- **HPA integration:** KEDA creates and owns the HPA; you just configure the ScaledObject

<br>

<blockquote>
Scale on what drives your load, not on what it looks like after the fact.
</blockquote>

---

<!-- KEDA Aurora defaults -->
## KEDA on Aurora

![bg left:20%](./img/aurora.png)

| Setting | Value |
|---------|-------|
| KEDA Version | 2.20.2 (latest stable) |
| Namespace | keda-system |
| Metrics Server | Enabled (required) |
| Prometheus/ServiceMonitor | Disabled (opt-in per workload) |

<br>

<blockquote>
KEDA is the platform-native way to scale replicas based on real demand signals.
</blockquote>

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
- **Use KEDA alongside your own HPA** - KEDA creates and manages the HPA; you configure only the ScaledObject
- **Rely on short cooldowns for isolation** - `cooldownPeriod` (default 300s) only affects the final scale-from-zero, not general scale-down (that's HPA's `behavior` window)

### DO:
- Keep `minReplicaCount: 1`+ in production (no scale-to-zero)
- Add `terminationGracePeriodSeconds` for long-running consumers
- Use `ScaledJob` for event-processing batch work
- Validate across a full 24-hour cycle in non-prod

> **Tip:** Think of KEDA as the "HPA service" - you configure what to scale (ScaledObject), KEDA manages the actual HPA controller behind the scenes.

> **That's the 'how many' axis.** Next: Karpenter provisions *what capacity* to fit the pods.

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
    <div class="plate">Bin-packs all pending pods</div>
    <div class="plate">Cheapest exact-fit node</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Consolidate</div>
    <div class="plate">Repack & remove idle</div>
    <div class="plate">Respects Pod Distribution Budgets</div>
  </div>
</div>

> **The Big Shift:** Karpenter bypasses Node Groups entirely. It talks directly to the cloud API with bin-packing intelligence.

---

<!-- Karpenter deep dive -->
## How Karpenter Works: Three Steps

![bg left:20%](./img/aurora.png)

| Step | What Happens | Why It Matters |
|------|-------------|----------------|
| **1. Watch** | Event-driven: Watches unschedulable pods *millisecond-by-millisecond* | No polling delay → ~45s scale-up |
| **2. Provision** | Bin-packs all pending pods onto the *cheapest exact-fit* node | 3-4 pods on one $15/mo node, not 3x $100/mo nodes |
| **3. Consolidate** | Repacks workloads, removes idle nodes (empty, single-node swap, multi-node) | Saves 20-40% vs Cluster Autoscaler |

**Key capabilities:**
- **Direct API access:** No Auto Scaling Groups - spins up one perfect node per demand
- **Bin-packing:** Aggregates all pending pods, finds optimal layout
- **Respects Pod Distribution Budgets:** Will wait to drain nodes until PDBs allow; never force-terminates pods during consolidation
- **Node attributes:** Reads nodeSelector, affinity, tolerations, GPU requirements

<br>

<blockquote>
Cluster Autoscaler adds to pre-defined pools. Karpenter builds the perfect node per pod demand.
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
## Karpenter on Aurora

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

<br>

<blockquote>
Learn Karpenter. Use CSP NAP if it works. Switch back to self-hosted if constraints emerge.
</blockquote>

---

<!-- Karpenter limitations -->
## Karpenter: Risks and Caveats

![bg left:20%](./img/aurora.png)

- **GCP provider is community-maintained:** the [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp) is pre-1.0; breaking changes happen. Pin versions, scan, and keep GKE Workload Autoscaler as fallback
- **Node churn:** aggressive consolidation disrupts pods; tune `consolidateAfter` and use PodDisruptionBudgets
- **Azure NAP (managed Karpenter):** simpler now, but [github.com/Azure/karpenter-provider-azure/issues/1351](https://github.com/Azure/karpenter-provider-azure/issues/1351) indicates current limitations; consider self-hosted for full control
- **Model change:** autoscaler choice is set at cluster creation time on all platforms
- **Set `limits`** on NodePool to prevent runaway provisioning
- **Learn Karpenter first:** understand the open-source project before choosing a managed variant

> **That's the infrastructure axis.** You now have: VPA (how much) + KEDA (how many) + Karpenter (what capacity) = a complete pipeline.

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

1. **KEDA** decides replica count (events, queues, schedules)
2. **VPA** sizes each pod based on usage history
3. **Combined:** Replica count × per-pod size = total pending-pod demand
4. **Karpenter** watches for unschedulable pods and provisions nodes

<br>

<blockquote>
All three feed one pipeline. Keep their axes decoupled to achieve optimal, right-sized scaling.
</blockquote>

---

<!-- Conflict rules -->
## The Rules That Keep Them From Fighting

![bg left:20%](./img/aurora.png)

| Pair | Rule |
|------|------|
| **VPA + HPA** | Never on the same resource. VPA = memory, HPA = CPU (`controlledResources`) |
| **VPA + KEDA** | Conflict only with CPU/memory triggers. Safe with queue depth, cron, or custom metrics |
| **KEDA + HPA** | Don't configure both KEDA's ScaledObject and your own HPA for the same deployment — KEDA creates and owns the underlying HPA automatically |
| **VPA + Karpenter** | Complementary: VPA changes requests, Karpenter repacks. Set VPA `maxAllowed` and NodePool `limits` |
| **KEDA 0 + Karpenter** | Scale-to-zero + consolidation empties and removes nodes. Watch cold-start latency |

> **What "your own HPA" means:** Creating a Kubernetes HorizontalPodAutoscaler manifest that targets the same deployment as a KEDA ScaledObject. Both autoscalers will fight over replica count, causing flapping and API thrashing.

---

<!-- Common Anti-Patterns -->
## Common Anti-Patterns

| Workload Scenario | The Anti-Pattern | The Result |
|-------------------|------------------|------------|
| **High-Volume IoT / Events** | HPA and KEDA fight over CPU | Pod counts oscillate, data dropped during peak traffic |
| **Heavy Compute Processing** | No budget limits on Karpenter | Massive cloud spending spike overnight |
| **Latency-Critical APIs** | Scale-to-zero in prod | 2-minute cold-start delay on unexpected events |
| **Standard Multi-Tier Apps** | VPA+HPA both on CPU | Rapid endless pod eviction (deployment flapping) |

> **Tip:** KEDA creates and owns the HPA. Don't create your own HPA for the same workload.

---

<!-- What Could Go Wrong -->
## What Could Go Wrong

![bg left:20%](./img/aurora.png)

**Autoscaling is like a high-performance jet engine.** If the control systems are out of sync, the wings start to vibrate violently—called *flapping*—until the sheer friction tears your availability apart.

| Failure Mode | What Happens | The Cost |
|--------------|--------------|----------|
| **Death Spiral** | HPA and VPA fight over CPU. Pods spin up, shrink, spike CPU, spin up again. | API server overload. User latency waves. |
| **Karpenter Whiplash** | Queue burst → 100 pods → $1000 node. Burst ends → 1 pod → node terminated. Repeat. | Massive cloud spend. Node instability. |
| **OOM Cascade** | Memory leak → VPA raises memory → leak consumes more → node OOM → kernel kills all pods. | Single app takes down everything on the node. |
| **Phantom Capacity** | KEDA scales to 200, Karpenter orders Spot nodes. Spot unavailable → KEDA jumps to 400. | 500 pods booted for 200 of demand. |

> **Remember:** Keep metrics decoupled. VPA (memory), KEDA (CPU/traffic), Karpenter (pending pods).

---

<!-- Conclusion -->
## Conclusion

![bg left:20%](./img/aurora.png)

- **VPA** right-sizes pods (how much)
- **KEDA** scales replicas on real demand, including to zero (how many)
- **Karpenter** provisions and consolidates nodes (what capacity)
- **Together, they form a single scaling engine:** keep their metrics decoupled and their efficiency multiplies.

<br>

<blockquote>
Right-size the pods, scale on real demand, provision only what fits.
</blockquote>

---

<!-- Afterword: FAQs -->
## Appendix: FAQs

![bg left:20%](./img/aurora.png)

---

### Group 1: Architectural & Tooling Questions

**Q: Why KEDA instead of plain HPA with custom/external metrics? HPA v2 already supports those.**

A: While HPA v2 supports custom metrics, it requires deploying and maintaining complex Prometheus Adapter infrastructure. KEDA is entirely plug-and-play with 60+ built-in event sources. More importantly, native HPA cannot scale to zero—it can only scale down to 1. KEDA is the only mechanism that allows true zero resource consumption when idle.

---

**Q: VPA and HPA can't both touch CPU — so how do I scale a web app on CPU and right-size it?**

A: We decouple the metrics. For typical web apps, we assign HPA to manage CPU (handling unpredictable traffic spikes by scaling out) and VPA to manage Memory (right-sizing the baseline footprint over time). If we must right-size CPU, we run VPA in Initial mode—it benchmarks CPU requests only at pod birth, then hands total scaling control to the HPA.

---

**Q: If autoscaler choice is fixed at cluster creation, what's the migration path from Cluster Autoscaler to Karpenter?**

A: It's a safe blue-green migration. Karpenter can run simultaneously alongside Cluster Autoscaler. We deploy Karpenter, introduce a new NodePool, and slowly taint or scale down the old Managed Node Groups. Workloads naturally drain from CAS and land on Karpenter-provisioned hardware without cluster recreation.

---

### Group 2: Stability, Blast Radius & Availability

**Q: Karpenter consolidation + my PodDisruptionBudgets + spot interruptions — what actually happens to my availability?**

A: Kubernetes native controls always win. Karpenter strictly respects Pod Distribution Budgets. If a consolidation or spot replacement violates your Pod Distribution Budget, Karpenter aborts the move. For critical workloads, we can inject `karpenter.sh/do-not-disrupt: "true"` to lock pods to their current node permanently.

---

**Q: What's the blast radius / rollback story if VPA recommends something terrible in Initial or InPlace mode?**

A: The blast radius is tightly constrained. We enforce safety rails using VPA `minAllowed` and `maxAllowed` limits so rogue recommendations can never starve or balloon a pod. If a bad update goes live, rollback is instant: delete the VPA object or change its mode to Off, and manually hardcode the last-known-stable resource requests in your deployment manifest.

---

**Q: Scale-to-zero cold starts — how bad, and how do I mitigate (keep-warm, min replicas)?**

A: The cold start is real—typically 1-3 minutes if Karpenter must provision a raw node from scratch. We mitigate based on application tier: Tier-1 customer-facing apps are barred from scaling to zero (`minReplicas: 1`). For async workers, we accept the delay or use Karpenter headroom to keep small buffers of empty, pre-warmed capacity ready.

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
5. <a href="https://github.com/Azure/karpenter-provider-azure/issues/1351">Azure NAP Issue #1351</a>
6. VPA / KEDA usage guides and the Karpenter autoscaling proposal (docs-main)

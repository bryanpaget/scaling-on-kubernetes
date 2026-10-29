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

Scaling on Aurora: how three autoscalers fit together on different axes

- **VPA** Vertical Pod Autoscaler: right-sizes pod CPU/memory requests
- **KEDA** Kubernetes Event-driven Autoscaling: including scale-to-zero
- **Karpenter**: Cloud-agnostic, just-in-time node provisioning and consolidation

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
    <div class="plate plate-head">VPA</div>
    <div class="plate">Sizes pod resources</div>
    <div class="plate">Adjusts requests & limits</div>
    <div class="plate"><i>(How big is each pod)</i></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">KEDA</div>
    <div class="plate">Scales replica count</div>
    <div class="plate">Driven by events & queues</div>
    <div class="plate"><i>(How many pods)</i></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">Karpenter</div>
    <div class="plate">Provisions right-sized nodes</div>
    <div class="plate">Binds pending pods to compute</div>
    <div class="plate"><i>(Where pods fit)</i></div>
  </div>
</div>

<br>

<blockquote>
Replica count × per-pod size = pending-pod demand that Karpenter satisfies.
</blockquote>

> **Rule of thumb:** never point HPA and VPA at the same resource (CPU or memory).

---

<!-- ============================ PART 1: VPA ============================ -->
<!-- VPA section divider -->
# Part 1: VPA
## Vertical Pod Autoscaling
### Right-sizing pod resources

![bg left:30%](./img/aurora.png)

---

<!-- What is VPA -->
## What is VPA?

**Vertical Pod Autoscaler** adjusts the CPU and memory requests and limits of pods based on observed usage, within boundaries you define.

- **Targets:** workload CPU/memory requests & limits
- **Workloads:** Deployments, StatefulSets, DaemonSets
- **Architecture:** Recommender, Updater, Admission Controller
- **Configuration:** use `controlledValues: RequestsOnly` to keep your own limits

<br>

<blockquote>
HPA scales how many; VPA scales how much. Tip: start VPA in `Off` mode to gather data before enabling recommendations.
</blockquote>

---

<!-- Why VPA matters -->
## Why VPA: Day-Zero Right-Sizing

The static baseline trap: engineers hardcode generic resource values at deploy time and never revisit them.

**`Initial` mode sizes pods at creation.** VPA acts as a smart template injector at birth, with no production restart risk.

- **Mutating at birth:** the Admission Controller intercepts pod creation before scheduling
- **Profiles over guesses:** VPA replaces hardcoded values with data-driven targets based on usage history
- **Zero churn:** once a pod is running, its resources are locked. VPA never evicts or restarts a live container

<blockquote>
Lock in optimal footprints at birth, with zero runtime risk.
</blockquote>

---

<!-- How VPA works -->
## How VPA Works

Three components, one pipeline:

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
    <div class="plate">Compares recs to current requests</div>
    <div class="plate">Decides when to act</div>
    <div class="plate">Respects PDBs & rollout strategy</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Admission Controller</div>
    <div class="plate">Intercepts pod creation</div>
    <div class="plate">Applies recommendations</div>
    <div class="plate">Mutates requests at birth</div>
  </div>
</div>

---

The Recommender watches metrics continuously and emits four values into VPA status:

| Value | Meaning |
|-------|---------|
| **Target** | The sweet spot injected into new pods |
| **Lower bound** | Under-provisioned floor; breach triggers upscale |
| **Upper bound** | Over-provisioned ceiling; idling triggers downscale |
| **Uncapped target** | Raw demand, ignoring your YAML safety caps |

> A wide gap between Target and Uncapped Target means your safety rails are throttling performance.

---

<!-- VPA modes -->
## VPA Modes: A Risk Spectrum

Each mode trades runtime stability against resource efficiency.

<div class="flow" style="font-size: 0.85em; gap: 12px;">

  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head" style="background: linear-gradient(135deg, #1e88e5 0%, #42a5f5 100%);">Off</div>
    <div class="plate">Analysis only</div>
    <div class="plate">No updates</div>
    <div class="plate" style="font-size:17px; padding:8px;">Writes recommendations to status without touching the cluster.</div>
  </div>

  <div class="flow-arrow">&rarr;</div>

  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head" style="background: linear-gradient(135deg, #26a69a 0%, #80cbc4 100%);">Initial</div>
    <div class="plate">Sized at birth</div>
    <div class="plate">No evictions</div>
    <div class="plate" style="font-size:17px; padding:8px;"><b>Our default on Aurora.</b> Injects targets only at pod creation.</div>
  </div>

  <div class="flow-arrow">&rarr;</div>

  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head" style="background: linear-gradient(135deg, #f57c00 0%, #ffca28 100%);">InPlace</div>
    <div class="plate">Live resizing</div>
    <div class="plate">No evictions*</div>
    <div class="plate" style="font-size:17px; padding:8px;">Resizes containers inside cgroups without dropping the process.</div>
  </div>

  <div class="flow-arrow">&rarr;</div>

  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head" style="background: linear-gradient(135deg, #e53935 0%, #ff7043 100%);">Recreate</div>
    <div class="plate">Hard eviction</div>
    <div class="plate">Yes evictions</div>
    <div class="plate" style="font-size:17px; padding:8px;">Use rarely. Restarts containers to resize them on boot.</div>
  </div>

</div>

<br>

> \* InPlace falls back to a standard rolling eviction if a node is full or the runtime cannot flex. If you want that fallback explicitly, use `InPlaceOrRecreate`.

---

<!-- In-place resizing -->
## In-Place Resizing: Live Right-Sizing

Changes resource boundaries on the fly, with zero restarts or evictions. Four things must hold:

<div class="flow" style="font-size: 0.85em; gap: 12px; margin-top: 20px;">

  <div class="flow-box" style="width: 24%;">
    <div class="plate plate-head">Runtime Support</div>
    <div class="plate">Elastic sizing</div>
    <div class="plate" style="font-size:16px; padding:8px;">CPU scales freely. Memory needs dynamic cgroup tracking (e.g., JVM dynamic heap bounds).</div>
  </div>

  <div class="flow-box" style="width: 24%;">
    <div class="plate plate-head">Node Headroom</div>
    <div class="plate">Physical space</div>
    <div class="plate" style="font-size:16px; padding:8px;">The host must have spare capacity to grant an upward resize.</div>
  </div>

  <div class="flow-box" style="width: 24%;">
    <div class="plate plate-head">Downscale Caution</div>
    <div class="plate">OOM risk</div>
    <div class="plate" style="font-size:16px; padding:8px;">Shrinking memory too aggressively triggers instant kernel OOM kills.</div>
  </div>

  <div class="flow-box" style="width: 24%;">
    <div class="plate plate-head">Platform Support</div>
    <div class="plate">Feature gate active</div>
    <div class="plate" style="font-size:16px; padding:8px;">Requires Kubernetes v1.27+ in-place resize support in the control plane.</div>
  </div>

</div>

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

---

<!-- VPA limitations -->
## VPA: When Not to Use It

![bg left:20%](./img/aurora.png)

- **Spiky workloads:** VPA reacts to history; sudden bursts stay under-provisioned until it catches up
- **JVM / heap-tuned apps:** raising memory requests does not change `-Xmx`; size the runtime, not just the pod
- **Eviction-sensitive workloads:** avoid `Recreate` mode where restarts are costly
- **Same resource as another autoscaler:** never let two controllers fight over CPU/memory (see Part 4)
- **Very short-lived processes:** VPA needs time to collect and analyze usage data

<br>

> That's the "how much" axis. Next: KEDA decides how many replicas you need.

---

<!-- ============================ PART 2: KEDA ============================ -->
<!-- KEDA section divider -->
# Part 2: KEDA
## Kubernetes Event-Driven Autoscaling

![bg left:30%](./img/aurora.png)

### Scaling replicas on real-world demand

---

<!-- What is KEDA -->
## What is KEDA?

**Kubernetes Event-Driven Autoscaler:** a metrics broker that connects external event sources to native Kubernetes horizontal scaling.

- **Metric broker:** bridges cloud and on-prem event streams without custom adapters
- **Beyond CPU/memory:** scales on queue depth, schedules, and custom metrics
- **Scale-to-zero:** the standard, reliable way in Kubernetes to scale a workload to zero replicas
- **CRD-driven:** `ScaledObject` for Deployments/StatefulSets, `ScaledJob` for batch work

<br>

<blockquote>
HPA watches the consequence of load (CPU). KEDA watches the origin of load (events). Scale-to-zero trades cost for cold-start latency — tuning cooldown and stabilization windows controls scale-down timing.
</blockquote>

---

<!-- KEDA architecture -->
## KEDA Architecture: Two Controllers

KEDA splits responsibilities so scaling stays fast without burdening the cluster control plane.

<div class="flow">
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">Telemetry Sources</div>
    <div class="plate">Kafka lag</div>
    <div class="plate">RabbitMQ depth</div>
    <div class="plate">Prometheus queries</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">KEDA Metrics Server</div>
    <div class="plate"><b>Supplies metrics for 1 → N scaling</b></div>
    <div class="plate">Exposes external metrics to HPA v2</div>
    <div class="plate">HPA calculates replica count</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">KEDA Operator</div>
    <div class="plate"><b>Handles the 0 ↔ 1 boundary</b></div>
    <div class="plate">Polls and activates triggers</div>
    <div class="plate">Patches <code>spec.replicas</code> at zero</div>
  </div>
</div>

<br>

> One pipeline, two engines: the Operator wakes a workload from zero; the Metrics Server supplies metrics that HPA uses from one upward.

---

<!-- KEDA scale-to-zero -->
## KEDA Scale-to-Zero: How It Works

Native HPA cannot evaluate a workload at zero replicas, so KEDA handles the zero boundary itself.

<div class="flow">
  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head">Idle Phase</div>
    <div class="plate">Workload at 0 replicas</div>
    <div class="plate">Native HPA dormant</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head">Active Probing</div>
    <div class="plate">KEDA Operator watches</div>
    <div class="plate">Polls event stream every <code>pollingInterval</code></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head">Kickstart</div>
    <div class="plate">Events arrive</div>
    <div class="plate">Patches <code>spec.replicas</code> 0 → 1</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head">Hand-Off</div>
    <div class="plate">HPA activates at 1 pod</div>
    <div class="plate">Metrics Server supplies 1 → N values</div>
  </div>
</div>

---

<!-- KEDA example -->
## KEDA: ScaledObject Example

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: threat-analyzer-scaler
spec:
  scaleTargetRef:
    name: threat-analyzer
  pollingInterval: 1            # Redis is polled every second
  cooldownPeriod: 15            # Hold active state before scale-to-zero
  minReplicaCount: 0            # True scale-to-zero
  maxReplicaCount: 10           # Hard ceiling
  triggers:
  - type: redis
    metadata:
      address: redis-service:6379
      listName: security-alerts
      listLength: "5"           # Target: 5 queued items per replica
      activationListLength: "1" # Wake from zero on the first item
```

**What the HPA shows:** `14/5 (avg)` means 14 queued items divided by the target of 5.
The HPA estimates 3 replicas, while its own `MINPODS` may read `1` at runtime; KEDA still owns the zero boundary.

---

<!-- Live Redis demo -->
## Live Demo: Queue Burst → Scale Out → Scale Down

<div class="flow" style="display: flex; align-items: stretch; gap: 12px;">
  <div class="flow-box" style="width: 23%;"><div class="plate plate-head">1. Idle</div><div class="plate">0 workers</div><div class="plate">Queue length: 0</div></div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;"><div class="plate plate-head">2. Burst</div><div class="plate">Add 500 items</div><div class="plate">Queue spikes</div></div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;"><div class="plate plate-head">3. Scale out</div><div class="plate">HPA reads backlog</div><div class="plate">Workers drain items</div></div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;"><div class="plate plate-head">4. Scale down</div><div class="plate">Queue reaches 0</div><div class="plate">Cooldown → 0 workers</div></div>
</div>

<br>

> Verify consumption, not just replica count. A growing queue alone does not prove that workers can reach Redis or process the data.

```bash
kubectl exec -n keda-system $(kubectl get pod -n keda-system -l app=redis -o jsonpath='{.items[0].metadata.name}') -- redis-cli EVAL 'for i=1,500 do redis.call("RPUSH","security-alerts","demo-"..i) end return 500' 0
```

The 500-item burst separates the queue spike from the built-in wave generator's continuous traffic.

---

<!-- Networking lesson -->
## Scale-to-Zero Demo: Network Path Is a Dependency

The Redis demo deliberately uses Cilium network policies in a default-deny environment.
Allowed paths are explicit:

- Load generator → Redis on TCP `6379`
- Threat analyzer workers → Redis on TCP `6379`
- KEDA operator → Redis to activate and poll metrics
- KEDA metrics/API components → Kubernetes API and metrics traffic

**Lesson:** autoscaling can appear healthy while Redis traffic is blocked. Watch queue depth, worker logs, ScaledObject status, HPA replicas, and pod connectivity together.

---

<!-- Trigger portfolio -->
## Production Trigger Portfolio on Aurora

KEDA is not just message queues. Mix scaler types across the topology.

<div class="flow" style="display: flex; justify-content: space-between; align-items: stretch; gap: 15px;">

  <div class="flow-box" style="width: 32%; background: rgba(0, 0, 0, 0.02); padding: 10px; border-radius: 6px; border-top: 4px solid #2d7d9a;">
    <div class="plate plate-head" style="background: #2d7d9a;">Telemetry Trigger</div>
    <div class="plate"><b>Prometheus / Thanos Scaler</b></div>
    <div class="plate" style="font-size: 0.9em; text-align: left; padding: 5px 0;">Scale on live traffic dynamics.</div>
    <div class="plate" style="font-size: 0.85em; color: #4A5568; text-align: left;">
      • Inbound request velocity (RPS)<br>
      • HTTP error-rate spikes<br>
      • Database query delays
    </div>
  </div>

  <div class="flow-box" style="width: 32%; background: rgba(0, 0, 0, 0.02); padding: 10px; border-radius: 6px; border-top: 4px solid #2b6cb0;">
    <div class="plate plate-head" style="background: #2b6cb0;">Predictive Trigger</div>
    <div class="plate"><b>Cron / Calendar Scaler</b></div>
    <div class="plate" style="font-size: 0.9em; text-align: left; padding: 5px 0;">Pre-warm for known schedules.</div>
    <div class="plate" style="font-size: 0.85em; color: #4A5568; text-align: left;">
      • Spin up before shifts log in<br>
      • Force scale-down in quiet windows<br>
      • Avoids slow cold-starts
    </div>
  </div>

  <div class="flow-box" style="width: 32%; background: rgba(0, 0, 0, 0.02); padding: 10px; border-radius: 6px; border-top: 4px solid #2f855a;">
    <div class="plate plate-head" style="background: #2f855a;">Safety Fallback</div>
    <div class="plate"><b>CPU / Memory Trigger</b></div>
    <div class="plate" style="font-size: 0.9em; text-align: left; padding: 5px 0;">Protect capacity if event loops degrade.</div>
    <div class="plate" style="font-size: 0.85em; color: #4A5568; text-align: left;">
      • Secondary layer on top of events<br>
      • Fires if the queue stalls<br>
      • Prevents app exhaustion
    </div>
  </div>

</div>

<br>

> **Design rule:** bind triggers to credentials with `TriggerAuthentication` CRDs — never put secrets in ScaledObject manifests.

---

<!-- ============================ PART 3: Karpenter ============================ -->
<!-- Karpenter section divider -->
# Part 3: Karpenter
## Open-source, cloud-agnostic node autoscaler
### Just-in-time node provisioning

![bg left:30%](./img/aurora.png)

---

<!-- What is Karpenter -->
## What is Karpenter?

**Cloud-agnostic node autoscaler:** provisions nodes just-in-time for pending pods, then consolidates underutilized capacity.

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">Watch</div>
    <div class="plate">Unschedulable pods</div>
    <div class="plate">Event-driven, no polling</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Provision</div>
    <div class="plate">Bin-packs pending pods</div>
    <div class="plate">Cheapest exact-fit node</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Consolidate</div>
    <div class="plate">Repack & remove idle nodes</div>
    <div class="plate">Respects Pod Disruption Budgets</div>
  </div>
</div>

<br>

> **The big shift:** Karpenter bypasses node groups and talks directly to the cloud API, choosing capacity per demand instead of growing pre-defined pools.

---

<!-- How Karpenter works -->
## How Karpenter Works: Three Steps

| Step | What happens | Why it matters |
|------|-------------|----------------|
| **1. Watch** | Watches unschedulable pods event-by-event | No polling delay; vendor-reported scale-up in ~45–60s |
| **2. Provision** | Bin-packs pending pods onto the cheapest exact-fit node | Several pods share one cheap node instead of over-provisioning pools |
| **3. Consolidate** | Repacks workloads, drains and terminates underutilized nodes | Continuous right-sizing instead of periodic cleanup |

**Key capabilities:**
- Direct cloud API access — one purpose-built node per demand wave, no Auto Scaling Groups
- Bin-packing across all pending pods at once
- Reads `nodeSelector`, affinity, tolerations, and GPU requirements before choosing capacity
- Drains respect PodDisruptionBudgets; never force-terminates pods during consolidation

> Cluster Autoscaler grows pre-defined pools. Karpenter builds the right node per demand wave, then reclaims what is no longer needed.

---

<!-- Karpenter vs CA -->
## Karpenter vs Cluster Autoscaler

![bg left:20%](./img/aurora.png)

| Aspect | Cluster Autoscaler | Karpenter |
|--------|-------------------|-----------|
| Node provisioning | Adds nodes to a node group, one at a time | Provisions a purpose-built node for pending pods |
| Instance selection | Expanders (least-waste, price, priority) | Cheapest instance type that fits, across families |
| Consolidation | Removes underutilized nodes after drain | Continuous repacking and node removal |
| Capacity mix | One pool per node group | Spot and on-demand mixed in one NodePool |
| Provisioning speed | Minutes | ~45–60s (vendor benchmark) |

> Vendor case studies report 20–40% cost reduction vs Cluster Autoscaler ([AWS example](https://repost.aws/articles/AR5C03QTEyRgKoDI-XO5UC7w/optimizing-your-amazon-eks-compute-costs-with-karpenter)). Validate in your own pilot before quoting numbers internally.

---

<!-- Karpenter NodePool -->
## Karpenter: NodePool as Source of Truth

![bg left:20%](./img/aurora.png)

Define compute intent once; the provider-specific `nodeClassRef` adapts it per platform (EC2NodeClass, AKSNodeClass, GKENodeClass, ...).

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        name: default           # EC2NodeClass, AKSNodeClass, etc. (provider-specific)
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

<!-- Karpenter on Aurora -->
## Karpenter on Aurora

![bg left:20%](./img/aurora.png)

**Goal:** build in-house Karpenter expertise that works across clouds, falling back to CSP-managed options when they are sufficient.

- **AWS:** self-hosted Karpenter (v1 provider, full control)
- **Azure:** try AKS NAP (managed Karpenter); switch to self-hosted if constraints appear
- **GKE:** self-hosted Karpenter via the [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp)
- **On-premises:** self-hosted (you own the infrastructure)

**Why self-hosted when possible:**
- Same NodePool APIs across all platforms
- Full version control and security scanning
- No vendor lock-in on provisioning behavior

> Learn Karpenter first. Use the managed variant if it works; switch back to self-hosted if constraints emerge.

---

<!-- Karpenter limitations -->
## Karpenter: Risks and Caveats

- **GCP provider is community-maintained:** the [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp) is pre-1.0 and breaking changes happen. Pin versions, scan images, and keep GKE's workload autoscaler as a fallback
- **Node churn:** aggressive consolidation disrupts pods; tune `consolidateAfter` and protect critical workloads with PodDisruptionBudgets
- **Azure NAP:** simpler to run, but [issue #1351](https://github.com/Azure/karpenter-provider-azure/issues/1351) tracks current limitations; prefer self-hosted if you need full control
- **Cluster-creation decision:** the autoscaler model is chosen at cluster creation time on most platforms — decide before you build
- **Always set NodePool `limits`** to prevent runaway provisioning

> **That's the infrastructure axis.** You now have: VPA (how much) + KEDA (how many) + Karpenter (what capacity) — one complete pipeline.

---

<!-- ============================ PART 4: Interactions ============================ -->
<!-- Interactions divider -->
# Part 4: Putting It Together
## Interactions and anti-patterns
### Tips and tricks

![bg left:30%](./img/aurora.png)

---

<!-- Complete picture -->
## The Complete Picture

![bg left:20%](./img/aurora.png)

1. **KEDA** decides replica count (events, queues, schedules)
2. **VPA** sizes each pod based on usage history
3. **Combined:** replica count × per-pod size = total pending-pod demand
4. **Karpenter** watches for unschedulable pods and provisions nodes

<br>

> All three feed one pipeline. Keep their axes decoupled and their efficiency multiplies.

---

<!-- Conflict rules -->
## The Rules That Keep Them From Fighting

| Pair | Rule |
|------|------|
| **VPA + HPA** | Never on the same resource. Give VPA memory, HPA CPU (`controlledResources`) |
| **VPA + KEDA** | Conflict only with CPU/memory triggers. Safe with queue depth, cron, and custom metrics |
| **KEDA + HPA** | Do not create your own HPA for a deployment that has a KEDA ScaledObject — KEDA creates and owns the HPA |
| **VPA + Karpenter** | Complementary: VPA changes requests, Karpenter repacks. Set VPA `maxAllowed` and NodePool `limits` |
| **KEDA 0 + Karpenter** | Scale-to-zero plus consolidation empties and removes nodes. Watch cold-start latency |

> "Your own HPA" means a separate `HorizontalPodAutoscaler` manifest targeting the same deployment. Two controllers fighting over replica count causes flapping and API thrashing.

---

<!-- Anti-patterns -->
## Common Anti-Patterns

| Workload scenario | The anti-pattern | The result |
|-------------------|------------------|------------|
| **High-volume IoT / events** | HPA and KEDA both on CPU | Pod counts oscillate; data dropped at peak |
| **Heavy compute processing** | No budget limits on Karpenter | Overnight cloud spend spike |
| **Latency-critical APIs** | Scale-to-zero in production | Cold-start delay on unexpected events |
| **Standard multi-tier apps** | VPA and HPA both on CPU | Rapid eviction loop; deployment flapping |

> KEDA creates and owns the HPA. Don't add a second one for the same workload.

---

<!-- What could go wrong -->
## What Could Go Wrong

Autoscaling behaves like a feedback system: when the controllers fall out of sync, they oscillate ("flap") until availability breaks.

| Failure mode | What happens | The cost |
|--------------|--------------|----------|
| **Death spiral** | HPA and VPA fight over CPU: pods spin up, shrink, spike CPU, spin up again | API server overload; user-facing latency waves |
| **Karpenter whiplash** | Queue burst → 100 pods → big node. Burst ends → 1 pod → node terminated. Repeat. | Cloud spend; node churn instability |
| **OOM cascade** | Memory leak → VPA raises memory → leak consumes more → node OOM → kernel kills all pods on the node | One app takes down its neighbors |
| **Phantom capacity** | KEDA wants 200 replicas; Karpenter orders Spot; Spot unavailable → KEDA jumps to 400 | 500 pods scheduled for 200 of demand |

> **Principle:** keep metrics decoupled — VPA on memory, KEDA on events/traffic, Karpenter on pending pods.

**Real-world example:** VPA raises requests → Karpenter buys a bigger node → cost spikes. Check the combined impact before changing any knob.

---

<!-- Conclusion -->
## Conclusion

![bg left:20%](./img/aurora.png)

- **VPA** right-sizes pods (how much)
- **KEDA** scales replicas on real demand, including to zero (how many)
- **Karpenter** provisions and consolidates nodes (what capacity)
- **Together** they form one scaling engine — keep their metrics decoupled and the efficiency multiplies

<br>

<blockquote>
Right-size the pods, scale on real demand, provision only what fits.
</blockquote>

---

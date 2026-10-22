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
    <div class="plate">Respects Pod Disruption Budgets/rollout</div>
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

1. **Continuous Monitoring**
   Pulls real-time resource utilization from Metrics Server/Prometheus.
2. **Historical Analysis**
   Applies a decaying moving average where peaks matter most to eliminate OOMs.
3. **Target Generation**
   Calculates and writes a **4-zone boundary profile** to the VPA Status field:
   * **Target:** The optimal resource sweet spot injected into your pods.
   * **Lower Bound:** The under-provisioned warning track; triggers an upscale if breached.
   * **Upper Bound:** The over-provisioned waste ceiling; triggers a downscale if idling.
   * **Uncapped Target:** True raw application demand ignoring your YAML safety caps.

<br>

<blockquote>
The Recommender establishes the safety rails; the Updater and Admission Controller enforce them.
</blockquote>

---

<!-- In-Place Resizing -->
## In-Place Resizing: Zero-Interruption Right-Sizing

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
## VPA: When NOT to Use It

![bg left:20%](./img/aurora.png)

- **Spiky workloads:** VPA reacts to history; sudden bursts can be under-provisioned until it catches up
- **JVM / heap-tuned apps:** changing memory requests does not change `-Xmx`; size the runtime, not just the pod
- **Eviction-sensitive workloads:** avoid `Recreate` where restarts are costly
- **Same resource as KEDA:** never let two controllers fight over the same resource (see Part 4)
- **Very short-lived processes:** VPA needs time to collect and analyze usage data

<br>

> **That's the 'how much' axis.** Next: KEDA decides *how many* replicas you need.

---

<!-- ============================ PART 2: KEDA ============================ -->
<!-- KEDA section divider -->
# Part 2: KEDA
## Kubernetes Event-Driven Autoscaling

![bg left:50%](./img/aurora.png)

### Scaling Replicas on Real-World Demand

---

<!-- What is KEDA: Deep Architectural Definition -->
## What is KEDA?

**Kubernetes Event-Driven Autoscaler:** An advanced metrics broker that unifies external event telemetry with native Kubernetes horizontal scaling.

- **The Metric Broker:** Bridges cloud/on-prem event streams directly to your workloads without complex custom adapters
- **Decoupled Metric Lifecycle:** Frees your autoscaling loops from standard infrastructure metrics (CPU/Memory)
- **True Down-Scaling:** Provides the only reliable framework within Kubernetes to scale a standard workload all the way to absolute zero replicas
- **CRD-Driven Orchestration:** Managed natively via `ScaledObject` (for Deployments/StatefulSets) and `ScaledJob` (for ephemeral batch loops)

<br>

<blockquote>
Standard HPA watches the consequence of load (CPU). KEDA watches the origin of load (Events).
</blockquote>

---

<!-- KEDA Architecture Deep Dive -->
## KEDA Architecture: The Dual-Controller Engine

KEDA splits its responsibilities into two sub-systems to maintain high performance without blocking your cluster control plane.

<div style="display: flex; justify-content: space-between; align-items: stretch; gap: 15px;">
  
  <!-- Column 1: Ingestion -->
  <div style="width: 30%; border: 1px dashed #777; padding: 10px; border-radius: 6px;">
    <div class="plate plate-head" style="background: #4A5568;">Telemetry Sources</div>
    <div class="plate">Kafka Lag</div>
    <div class="plate">RabbitMQ Depth</div>
    <div class="plate">Prometheus Queries</div>
  </div>

  <div style="display: flex; align-items: center; font-size: 1.5em; color: #2d7d9a;">&rarr;</div>

  <!-- Column 2: 1 to N Engine -->
  <div style="width: 32%; background: rgba(45, 125, 154, 0.1); padding: 10px; border-radius: 6px;">
    <div class="plate plate-head" style="background: #2d7d9a;">KEDA Metrics Server</div>
    <div class="plate"><b>Handles 1 &rarr; N Scaling</b></div>
    <div class="plate">Acts as an HPA v2 provider</div>
    <div class="plate">Native HPA polls every 15s</div>
  </div>

  <!-- Column 3: 0 to 1 Engine -->
  <div style="width: 32%; background: rgba(45, 125, 154, 0.1); padding: 10px; border-radius: 6px;">
    <div class="plate plate-head" style="background: #2d7d9a;">KEDA Operator</div>
    <div class="plate"><b>Handles 0 &harr; 1 Scaling</b></div>
    <div class="plate">Bypasses native HPA limits</div>
    <div class="plate">Directly patches pod replicas</div>
  </div>

</div>

<br>

<blockquote>
Telemetry Ingestion &rarr; Metrics Server (for scaling up) + Operator (for waking from zero).
</blockquote>

---

<!-- KEDA Scale-To-Zero Mechanics -->
## KEDA Scale-To-Zero: How It Actually Works

Scaling to zero requires deep coordination because a native Kubernetes HPA cannot evaluate a workload sitting at `0` replicas.

<div style="display: flex; justify-content: space-between; align-items: stretch; gap: 10px; font-size: 0.85em;">

  <!-- Step 1 -->
  <div style="width: 23%; background: rgba(0,0,0,0.03); padding: 10px; border-radius: 6px; border-top: 4px solid #718096;">
    <div style="font-weight: bold; color: #4A5568; margin-bottom: 5px;">1. The Idle Phase</div>
    <div style="font-size: 0.9em; line-height: 1.3;">
      The workload sits at <b>0 replicas</b>. Because there are no pods running, the native HPA has no active metrics to pull and falls completely dormant.
    </div>
  </div>

  <!-- Step 2 -->
  <div style="width: 23%; background: rgba(0,0,0,0.03); padding: 10px; border-radius: 6px; border-top: 4px solid #2d7d9a;">
    <div style="font-weight: bold; color: #2d7d9a; margin-bottom: 5px;">2. Active Probing</div>
    <div style="font-size: 0.9em; line-height: 1.3;">
      The <b>KEDA Operator</b> keeps watch. It independently polls your external event stream (e.g., Kafka) every <code>pollingInterval</code> seconds.
    </div>
  </div>

  <!-- Step 3 -->
  <div style="width: 23%; background: rgba(0,0,0,0.03); padding: 10px; border-radius: 6px; border-top: 4px solid #2b6cb0;">
    <div style="font-weight: bold; color: #2b6cb0; margin-bottom: 5px;">3. The Kickstart</div>
    <div style="font-size: 0.9em; line-height: 1.3;">
      Events arrive! The Operator wakes up, bypasses the HPA entirely, and directly patches the deployment's <code>spec.replicas</code> from <b>0 to 1</b>.
    </div>
  </div>

  <!-- Step 4 -->
  <div style="width: 23%; background: rgba(0,0,0,0.03); padding: 10px; border-radius: 6px; border-top: 4px solid #2f855a;">
    <div style="font-weight: bold; color: #2f855a; margin-bottom: 5px;">4. Engine Hand-Off</div>
    <div style="font-size: 0.9em; line-height: 1.3;">
      With 1 pod alive, the HPA activates. The <b>KEDA Metrics Server</b> takes over telemetry routing, feeding the HPA to handle heavy <b>1 &rarr; N scaling</b>.
    </div>
  </div>

</div>

<br>

<blockquote>
The Operator wakes the workload up; the Metrics Server scales it up.
</blockquote>
    <div class="plate plate-head">Hand-Off (1 → N)</div>
    <div class="plate">Metrics Server feeds HPA for heavy volume scaling</div>
  </div>
</div>

---

<!-- Advanced Production ScaledObject Example -->
## KEDA: ScaledObject Example

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: billing-processor-scaler
spec:
  scaleTargetRef:
    name: billing-processor-deployment
  pollingInterval: 15           # Frequency to poll the external event stream
  cooldownPeriod:  600          # Wait 10m before executing scale-down to 0
  minReplicaCount: 1            # Production baseline (Guarantees zero cold-starts)
  maxReplicaCount: 50           # Hard boundary ceiling
  advanced:
    restoreToOriginalReplicaCount: true
    horizontalPodAutoscalerConfig:
      behavior:                 # Native HPA stabilization profiles
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
          - type: Percent
            value: 10           # Smooth downscaling (max 10% reduction per step)
            periodSeconds: 60
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: kafka.aurora.svc:9092
        topic: payment-events
        consumerGroup: billing-group
        lagThreshold: "10"      # Target: 1 replica per 10 unread messages
```

---

<!-- Production Trigger Portfolio -->
## Production Trigger Portfolio on Aurora

Don't limit KEDA to basic message queues. Leverage alternative scalers across the enterprise topology.

- **Prometheus / Thanos Scaler:** Scale microservices based on HTTP Error Rates, Inbound Request Velocity (RPS), or query execution durations
- **Cron / Calendar Scaler:** Pre-warm clusters before business hours. Combine with `desiredReplicas` to force scale-ups before morning shifts log in
- **CPU/Memory Fallback:** KEDA can scale on standard system resource metrics if configured as a secondary trigger, providing a safe backup if your primary event stream becomes degraded

---

<!-- Security & Production Best Practices -->
## Aurora Rule: Secure KEDA Authentication

Never authenticate scalers via plaintext strings inside the spec. Always bind triggers to external targets using the `TriggerAuthentication` or `ClusterTriggerAuthentication` CRDs linked to `SecretProviderClasses`.

---

<!-- KEDA Production Guardrails -->
## KEDA Production Guardrails

### ⚠️ Scale-To-Zero Production Trap
**Risk:** Scaling APIs or critical consumers to 0 replicas guarantees 1-3 minute cold-start penalties
**Mitigation:** `minReplicaCount: 1` for Tier-1; reserve scale-to-zero for non-prod or async batch workers

### ⚖️ Stabilization Window Tuning
**Do not:** Control high-velocity scale-down with `cooldownPeriod`
**Do:** Use `advanced.horizontalPodAutoscalerConfig.behavior` for native HPA rules

### 🛡️ Telemetry & Observability
**Monitor:** `keda_metrics_adapter_scaler_errors` Prometheus counter
**Alert:** Broker credential expiration causes silent scaler failure

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
    <div class="plate">Respects Pod Disruption Budgets</div>
  </div>
</div>

<br>

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
- **Respects Pod Disruption Budgets:** Will wait to drain nodes until PDBs allow; never force-terminates pods during consolidation
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
---

<!-- FAQ Section moved to faq-en.md -->

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
## Vertical Pod Autoscaling
### Right-sizing pod resources

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

The **Static Baseline Trap**—engineers hardcode generic resource values at deployment and never change them.

### `Initial` Mode: Sizing at Pod Creation
VPA acts as a **smart template injector** at birth, completely removing production restart risks.

* **Mutating at Birth:** The Admission Controller intercepts pod creation requests *before* scheduling.
* **Telemetry over Guesses:** VPA strips hardcoded numbers and injects an exact, data-driven target based on background usage history.
* **Zero Production Churn:** Once a pod is running, resource settings are locked. VPA will **never evict or restart** a live container mid-flight.

<blockquote>
Profiles over predictions. Lock in optimal footprints at birth with zero runtime risk.
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

The **Recommender** calculates resource metrics but **never modifies running pods**.

1. **Monitor:** Pulls utilization data continuously from Prometheus / Metrics Server.
2. **Analyze:** Applies a decaying moving average heavily weighted toward usage peaks.
3. **Spit out 4 boundary targets to VPA Status:**
   * **Target:** Optimal sweet spot injected into pods.
   * **Lower Bound:** Under-provisioned floor; triggers an upscale if breached.
   * **Upper Bound:** Over-provisioned ceiling; triggers a downscale if idling.
   * **Uncapped Target:** True raw application demand, ignoring your YAML safety caps.

<blockquote>
<b>Target</b> is what the platform allows; <b>Uncapped Target</b> is what the code actually asked for. A massive gap means your safety rails are actively throttling performance.
</blockquote>

---
<!-- In-Place Resizing -->
## In-Place Resizing: Live Right-Sizing

Modifies resource boundaries **on the fly with zero restarts or evictions**.

### The Alignment Challenge: True Zero-Interruption
Dynamic resizing works natively, but it requires four production layers to align flawlessly:

* **The Code Runtime:** CPU scales naturally. Memory requires an elastic runtime (e.g., JVM configured with dynamic cgroup heap bounds).
* **The Node Headroom:** The underlying physical host must have spare capacity immediately available to grant the increase.
* **The Downscale Trap:** Shrinking memory too aggressively will trigger instant Linux kernel **OOM kills** on the container.
* **The Platform Engine:** Orchestrated entirely by Aurora via the `InPlacePodVerticalScaling` feature gate (K8s 1.27+).

<blockquote>
<b>Safety Net:</b> <code>InPlaceOrRecreate</code> acts as a fallback policy. If a node is full or the runtime fails to flex, it safely drops back to a standard rolling eviction.
</blockquote>

---

<!-- VPA Modes: Choose Your Risk Profile -->
## VPA Modes: Choose Your Risk Profile

Instead of a generic feature list, think of VPA modes as a spectrum balancing **Runtime Stability** against **Resource Efficiency**.

<div class="flow" style="font-size: 0.8em; align-items: stretch; gap: 8px;">

  <!-- Mode 1: Off -->
  <div class="flow-box" style="width: 24%; border-top: 4px solid #718096; background: rgba(0,0,0,0.02); padding: 8px; border-radius: 4px;">
    <div class="plate plate-head" style="background: #718096; margin-bottom: 5px;">1. Off</div>
    <div style="font-weight: bold; font-size: 0.85em; margin-bottom: 4px;">Analysis Only</div>
    <div>• Evicts Pods: <b>No</b></div>
    <div>• Live Updates: <b>No</b></div>
    <div style="margin-top: 5px; font-size: 0.9em; color: #4A5568;">Generates target logs inside Status without altering your cluster.</div>
  </div>

  <div class="flow-arrow" style="align-self: center;">&rarr;</div>

  <!-- Mode 2: Initial -->
  <div class="flow-box" style="width: 24%; border-top: 4px solid #2b6cb0; background: rgba(0,0,0,0.02); padding: 8px; border-radius: 4px;">
    <div class="plate plate-head" style="background: #2b6cb0; margin-bottom: 5px;">2. Initial</div>
    <div style="font-weight: bold; font-size: 0.85em; margin-bottom: 4px;">Sized at Birth</div>
    <div>• Evicts Pods: <b>No</b></div>
    <div>• Live Updates: <b>No</b></div>
    <div style="margin-top: 5px; font-size: 0.9em; color: #4A5568;"><b>Recommended for Prod.</b> Inject targets only at pod creation; zero flight restarts.</div>
  </div>

  <div class="flow-arrow" style="align-self: center;">&rarr;</div>

  <!-- Mode 3: InPlace -->
  <div class="flow-box" style="width: 24%; border-top: 4px solid #2f855a; background: rgba(0,0,0,0.02); padding: 8px; border-radius: 4px;">
    <div class="plate plate-head" style="background: #2f855a; margin-bottom: 5px;">3. InPlace</div>
    <div style="font-weight: bold; font-size: 0.85em; margin-bottom: 4px;">Live Flexing</div>
    <div>• Evicts Pods: <b>No*</b></div>
    <div>• Live Updates: <b>Yes</b></div>
    <div style="margin-top: 5px; font-size: 0.9em; color: #4A5568;">Dynamically resizes containers inside cgroups without dropping the process.</div>
  </div>

  <div class="flow-arrow" style="align-self: center;">&rarr;</div>

  <!-- Mode 4: Recreate -->
  <div class="flow-box" style="width: 24%; border-top: 4px solid #c53030; background: rgba(0,0,0,0.02); padding: 8px; border-radius: 4px;">
    <div class="plate plate-head" style="background: #c53030; margin-bottom: 5px;">4. Recreate</div>
    <div style="font-weight: bold; font-size: 0.85em; margin-bottom: 4px;">Hard Eviction</div>
    <div>• Evicts Pods: <b>Yes</b></div>
    <div>• Live Updates: <b>Yes</b></div>
    <div style="margin-top: 5px; font-size: 0.9em; color: #4A5568;"><b>Use Rarely.</b> Aggressively terminates running containers to resize them on boot.</div>
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

![bg left:30%](./img/aurora.png)

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

<div class="flow">
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">Telemetry Sources</div>
    <div class="plate">Kafka Lag</div>
    <div class="plate">RabbitMQ Depth</div>
    <div class="plate">Prometheus Queries</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">KEDA Metrics Server</div>
    <div class="plate"><b>Handles 1 → N Scaling</b></div>
    <div class="plate">HPA v2 provider</div>
    <div class="plate">Polls every 15s</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">KEDA Operator</div>
    <div class="plate"><b>Handles 0 ↔ 1 Scaling</b></div>
    <div class="plate">Bypasses HPA</div>
    <div class="plate">Patches spec.replicas</div>
  </div>
</div>

<br>

<blockquote>
Telemetry Ingestion → Metrics Server (scale-up) + Operator (scale-from-zero).
</blockquote>

---

<!-- KEDA Scale-To-Zero Mechanics -->
## KEDA Scale-To-Zero: How It Actually Works

Scaling to zero requires deep coordination because a native Kubernetes HPA cannot evaluate a workload sitting at `0` replicas.

<div class="flow">
  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head">The Idle Phase</div>
    <div class="plate">Workload at <b>0 replicas</b></div>
    <div class="plate">Native HPA dormant</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head">Active Probing</div>
    <div class="plate"><b>KEDA Operator</b> keeps watch</div>
    <div class="plate">Polls event stream every <code>pollingInterval</code></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head">The Kickstart</div>
    <div class="plate">Events arrive!</div>
    <div class="plate">Patches <code>spec.replicas</code> from <b>0 to 1</b></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 23%;">
    <div class="plate plate-head">Engine Hand-Off</div>
    <div class="plate">HPA activates with 1 pod</div>
    <div class="plate"><b>KEDA Metrics Server</b> handles 1 → N</div>
  </div>
</div>

<br>

<blockquote>
The Operator wakes the workload up; the Metrics Server scales it up.
</blockquote>

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

<!-- Production Trigger Portfolio on Aurora -->
## Production Trigger Portfolio on Aurora

Don't limit KEDA to basic message queues. Leverage alternative scalers across the enterprise topology.

<div class="flow" style="display: flex; justify-content: space-between; align-items: stretch; gap: 15px;">

  <!-- Trigger Box 1 -->
  <div class="flow-box" style="width: 32%; background: rgba(0, 0, 0, 0.02); padding: 10px; border-radius: 6px; border-top: 4px solid #2d7d9a;">
    <div class="plate plate-head" style="background: #2d7d9a;">Telemetry Trigger</div>
    <div class="plate"><b>Prometheus / Thanos Scaler</b></div>
    <div class="plate" style="font-size: 0.9em; text-align: left; padding: 5px 0;">Scale applications based on live traffic dynamics.</div>
    <div class="plate" style="font-size: 0.85em; color: #4A5568; text-align: left;">
      • Inbound Request Velocity (RPS)<br>
      • HTTP Error Rate Spike thresholds<br>
      • Database query execution delays
    </div>
  </div>

  <!-- Trigger Box 2 -->
  <div class="flow-box" style="width: 32%; background: rgba(0, 0, 0, 0.02); padding: 10px; border-radius: 6px; border-top: 4px solid #2b6cb0;">
    <div class="plate plate-head" style="background: #2b6cb0;">Predictive Trigger</div>
    <div class="plate"><b>Cron / Calendar Scaler</b></div>
    <div class="plate" style="font-size: 0.9em; text-align: left; padding: 5px 0;">Pre-warm infrastructure based on known schedules.</div>
    <div class="plate" style="font-size: 0.85em; color: #4A5568; text-align: left;">
      • Spin up capacity before shifts log in<br>
      • Force scale-down during quiet windows<br>
      • Overrides slow raw cold-starts
    </div>
  </div>

  <!-- Trigger Box 3 -->
  <div class="flow-box" style="width: 32%; background: rgba(0, 0, 0, 0.02); padding: 10px; border-radius: 6px; border-top: 4px solid #2f855a;">
    <div class="plate plate-head" style="background: #2f855a;">Safety Backup Trigger</div>
    <div class="plate"><b>CPU / Memory Fallback</b></div>
    <div class="plate" style="font-size: 0.9em; text-align: left; padding: 5px 0;">Protect capacity if event loops degrade.</div>
    <div class="plate" style="font-size: 0.85em; color: #4A5568; text-align: left;">
      • Configured as a secondary layer<br>
      • Triggers if message queue stalls<br>
      • Prevents underlying app exhaustion
    </div>
  </div>

</div>

<br>

<blockquote>
<b>Design Rule:</b> Bind triggers to business logic targets using the platform's <code>TriggerAuthentication</code> CRDs to keep credentials out of code repositories.
</blockquote>


---

<!-- ============================ PART 3: Karpenter ============================ -->
<!-- Karpenter section divider -->
# Part 3: Karpenter
## Open source, cloud-agnostic node autoscaler
### Just-in-time node provisioning

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
### Tips and Tricks

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

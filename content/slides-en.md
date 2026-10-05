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
## The Scaling Map: Four Axes

![bg left:20%](./img/aurora.png)

| Tool | Scales | Level | Trigger |
|------|--------|-------|---------|
| **HPA** | Replica count | Pod | CPU/memory/metrics |
| **VPA** | Resource requests | Pod | Usage history |
| **KEDA** | Replica count (incl. 0) | Pod | Events, schedules, queues |
| **Karpenter** | Nodes | Infrastructure | Pending pods |

<blockquote>
Workload scalers (HPA/VPA/KEDA) decide what pods need. Karpenter provides the capacity.
</blockquote>

---

<!-- How they layer -->
## How They Layer

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">KEDA / HPA</div>
    <div class="plate">Creates or removes pods</div>
    <div class="plate">(replica count)</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">VPA</div>
    <div class="plate">Sets each pod's</div>
    <div class="plate">CPU / memory requests</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Karpenter</div>
    <div class="plate">Provisions nodes to fit</div>
    <div class="plate">the resulting pods</div>
  </div>
</div>

<blockquote>
Replica decisions and size decisions both become pending-pod demand that Karpenter satisfies.
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

**Vertical Pod Autoscaler:** automatically adjusts CPU and memory resource *requests* for your containers

![bg left:20%](./img/aurora.png)

- Unlike HPA which scales *replicas*, VPA scales *resource requests*
- Works with Deployments, StatefulSets, DaemonSets
- Two-phase: Recommender (analyze) + Updater (apply)
- Kubernetes-native via Custom Resource Definitions

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
- **Continuous monitoring:** analyzes actual usage patterns
- **Automatic adjustment:** updates resource requests over time
- **Right-sizing:** optimizes cluster resource utilization

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
| **InPlace** | Yes (in-place) | No | Recommended for prod |
| **InPlaceOrRecreate** | Yes (fallback) | Yes | Balanced, dev/test |
| **Recreate** | Yes | Yes | Use rarely |
| **Auto** | Deprecated | Deprecated | Do not use |

**Key distinction:** "Initial" only updates new pods; "InPlace" updates existing pods without eviction.

> `InPlace` needs the `InPlacePodVerticalScaling` feature gate and a recent VPA, or it falls back to recreation.

---

<!-- Aurora VPA defaults -->
## VPA on Aurora: Platform Defaults

![bg left:20%](./img/aurora.png)

| Setting | Value |
|---------|-------|
| VPA Version | 0.13.0 (appVersion 1.8.0) |
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
        controlledResources: ["cpu", "memory"]
```

**Bounds matter:** `maxAllowed` caps a runaway recommendation; `minAllowed` keeps pods schedulable.

---

<!-- VPA limitations -->
## VPA: When NOT to Use It

![bg left:20%](./img/aurora.png)

- **Spiky workloads:** VPA reacts to history; sudden bursts can be under-provisioned until it catches up
- **JVM / heap-tuned apps:** changing memory requests does not change `-Xmx`; size the runtime, not just the pod
- **Eviction-sensitive workloads:** avoid `Recreate` where restarts are costly
- **Batch / short-lived jobs:** use KEDA Jobs; VPA needs time to observe usage
- **Same resource as HPA/KEDA:** never let two controllers fight over the same resource (see Part 4)

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
| KEDA Version | 2.20.2 |
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
- **Scale to zero in production** - keep `minReplicaCount: 1`+
- **Mix cron with CPU/memory triggers** - HPA takes the MAX, scaling gets unpredictable
- **Create your own HPA** for a KEDA-managed workload - KEDA owns it
- **Use short cooldowns** - use 300s+ in production

### DO:
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
| Pre-provisioning | Entire node pool | Single node that fits |
| Instance selection | First SKU in policy | Cheapest that fits |
| Consolidation | Empty pools only | Continuous repacking |
| Multi-family | Static pool | Many families, spot + on-demand |
| Provisioning speed | Minutes | ~45-60s (vendor benchmark) |

> Estimated 20-40% cost reduction vs Cluster Autoscaler ([AWS case study](https://repost.aws/articles/AR5C03QTEyRgKoDI-XO5UC7w/optimizing-your-amazon-eks-compute-costs-with-karpenter)) - validate in a pilot.

---

<!-- Karpenter NodePool -->
## Karpenter: NodePool as Source of Truth

![bg left:20%](./img/aurora.png)

Define intent once; deploy on every platform (AWS/Azure/on-prem natively, GKE via the CloudPilot provider).

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
spec:
  template:
    spec:
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
    cpu: "1000"
```

---

<!-- Karpenter Aurora -->
## Karpenter on Aurora: The Plan

![bg left:20%](./img/aurora.png)

- **Standard everywhere:** one NodePool/NodeClaim model across AWS, Azure, on-prem, GKE
- **AWS / Azure / on-prem:** first-party providers (Karpenter v1 is GA)
- **GKE:** no first-party provider; run via the open-source CloudPilot AI GCP provider (same APIs)
- **Fallback:** native GKE NAP + Custom Compute Classes, kept ready if the provider is unsuitable

> GKE provider is pre-1.0 and community-maintained: pin the version, scan it, keep the NAP fallback. Pilot before any production cutover.

---

<!-- Karpenter limitations -->
## Karpenter: Risks and Caveats

![bg left:20%](./img/aurora.png)

- **GKE dependency:** the CloudPilot provider is pre-1.0; breaking changes happen (track `MIGRATION.md`)
- **Node churn:** aggressive consolidation disrupts pods; tune `consolidateAfter` and use PDBs
- **Cost figures are benchmarks**, not Aurora measurements; establish your own baseline first
- **Model change:** switching autoscalers is done at cluster creation, not mid-workload
- **Set `limits`** so a runaway workload cannot provision unbounded capacity

---

<!-- ============================ PART 4: Interactions ============================ -->
<!-- Interactions divider -->
# Part 4: Putting It Together
## Interactions and anti-patterns

![bg left:30%](./img/aurora.png)

---

<!-- The combined picture -->
## The Combined Picture

![bg left:20%](./img/aurora.png)

1. **KEDA / HPA** decide replica count from events or schedules
2. **VPA** sets each pod's CPU/memory requests from usage history
3. Those pods become scheduling demand
4. **Karpenter** provisions the cheapest nodes that fit, then consolidates as demand changes

<blockquote>
Replica count x per-pod size = the pending-pod demand Karpenter satisfies. All three feed one pipeline.
</blockquote>

---

<!-- Conflict rules -->
## The Rules That Keep Them From Fighting

![bg left:20%](./img/aurora.png)

| Pair | Rule |
|------|------|
| **VPA + HPA** | Never on the same resource. VPA = memory, HPA = CPU (`controlledResources`) |
| **VPA + KEDA** | Same rule: KEDA is HPA underneath, so split the resource. Safe pairing otherwise |
| **KEDA + own HPA** | Do not create your own HPA; KEDA owns it (`transfer-hpa-ownership` if needed) |
| **VPA + Karpenter** | Complementary: VPA changes requests, Karpenter repacks. Set VPA `maxAllowed` and NodePool `limits` |
| **KEDA 0 + Karpenter** | Scale-to-zero + consolidation empties and removes nodes. Powerful, but watch cold-start latency |

---

<!-- Anti-patterns -->
## Anti-Patterns to Avoid

![bg left:20%](./img/aurora.png)

- **VPA and HPA/KEDA on the same metric** - they oscillate against each other
- **VPA `Recreate` on eviction-sensitive workloads** - prefer Initial/InPlace
- **Scale-to-zero in production** without accounting for cold start
- **No `maxAllowed` / no NodePool `limits`** - a bad recommendation can request a whole node, and Karpenter will provision it
- **Aggressive consolidation without PDBs** - node churn disrupts workloads

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

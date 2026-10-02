---

<!-- Executive Summary -->
## Executive Summary

![bg left:20%](./img/aurora.png)

- **What:** VPA automatically adjusts CPU and memory resource requests for your containers based on actual usage patterns
- **Why:** Right-size resources to reduce waste and improve cluster efficiency while HPA handles replica scaling
- **Risk:** Low - VPA is an open-source Kubernetes-native tool with proven stability; Aurora platform just needs to adopt it
- **Cost:** Minimal - runs as system components, <1% overhead on control plane

<blockquote>
Right-size your resources, not just your replicas.
</blockquote>

---

<!-- What is VPA? -->
## What is VPA?

**Vertical Pod Autoscaler (VPA):** Automatically adjusts CPU and memory resource *requests* for your containers

![bg left:20%](./img/aurora.png)

- Unlike HPA which scales *replicas*, VPA scales *resource requests*
- Works with Deployments, StatefulSets, DaemonSets
- Two-phase: Recommender (analyze) + Updater (apply)
- Kubernetes-native via Custom Resource Definitions

<blockquote>
HPA scales how many, VPA scales how much.
</blockquote>

**Learn more:** <a href="https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/README.md">VPA GitHub</a>

---

<!-- VPA vs HPA -->
## VPA vs HPA: Two Sides of Scaling

| Component | What it Scales | How it Works | When to Use |
|-----------|---------------|--------------|-------------|
| **HPA** | Number of replicas | Scales pods up/down based on metrics | CPU/memory utilization, custom metrics, off-hours scaling |
| **VPA** | Resource requests per container | Adjusts CPU/memory requests based on usage | Right-sizing container resources, reducing over-provisioning |

![bg left:20%](./img/aurora.png)

<blockquote>
HPA answers "how many pods?" VPA answers "how much resources per pod?"
</blockquote>

---

<!-- Why VPA Matters -->
## Why VPA Matters

![bg left:20%](./img/aurora.png)

### The Resource Request Problem:
- Over-provisioning: 500m CPU when 100m needed → wasted capacity
- Under-provisioning: 100m CPU when 500m needed → throttling
- Static requests: Never adjust after deployment

### VPA Solves This:
- **Continuous monitoring:** Analyzes actual usage patterns
- **Automatic adjustment:** Updates resource requests over time
- **Right-sizing:** Optimizes cluster resource utilization

<blockquote>
Stop guessing, start sizing with data.
</blockquote>

---

<!-- VPA Modes -->
## VPA Modes: Choose Your Risk Profile

![bg left:20%](./img/aurora.png)

| Mode | Updates Existing Pods | Evicts Pods | Production Use |
|------|----------------------|-------------|----------------|
| **Off** | No | No | Analysis only |
| **Initial** | No | No | Recommended for prod |
| **InPlace** | Yes (in-place) | No | Recommended for prod |
| **InPlaceOrRecreate** | Yes (fallback) | Yes | Balanced approach |
| **Recreate** | Yes | Yes | Use rarely |
| **Auto** | Deprecated | Deprecated | Do not use |

**Key distinction:** "Initial" only updates new pods, "InPlace" updates existing pods without eviction.

---

<!-- Recommended VPA Modes -->
## Recommended VPA Modes for Production

![bg left:20%](./img/aurora.png)

### For Production Workloads:
1. **Initial** - Safe, applies only on pod creation
2. **InPlace** - Zero disruption, updates in-place when possible

```yaml
# Initial mode - apply only on pod creation
updatePolicy:
  updateMode: "Initial"
```

```yaml
# InPlace mode - try in-place update, never evict
updatePolicy:
  updateMode: "InPlace"
```

### For Development/Testing:
- **InPlaceOrRecreate** - Balanced, tries in-place first
- **Recreate** - Most aggressive, evicts and recreates

---

<!-- Platform Defaults -->
## Aurora Platform Defaults

![bg left:20%](./img/aurora.png)

| Setting | Value | Description |
|---------|-------|-------------|
| VPA Version | 0.13.0 (appVersion 1.8.0) | Vertical Pod Autoscaler chart |
| Namespace | vpa-system | VPA components deployment |
| Metrics Server | Enabled | Required for VPA to collect usage metrics |
| Admission Controller | Enabled | Mutating webhook for pod creation |
| Prometheus/ServiceMonitor | Disabled | Can be enabled per workload |

**Deployment:** Via aurora-core chart in `vpa-system` namespace

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

<!-- VPA Lifecycle -->
## VPA Lifecycle: Recommendation to Application

![bg left:20%](./img/aurora.png)

1. **Workload runs** → Metrics server collects usage
2. **Recommender analyzes** → Calculates recommendations
3. **VPA CRD updated** → Recommendations stored
4. **New pods created** → Admission controller applies
5. **Updater evaluates** → Decides when to update existing pods

```yaml
# Check recommendations
kubectl describe vpa my-app-vpa

# Look for: recommendedContainerResources
```

---

<!-- Enabling VPA -->
## Enabling VPA on Your Workload

![bg left:20%](./img/aurora.png)

### Step 1: Platform-Level (Already Done)
```yaml
# In config/config.yaml (aurora-core)
components:
  vpa:
    enabled: true
    metricsServer:
      enabled: true  # Required
```

### Step 2: Workload-Level (Your Turn)
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app-vpa
  namespace: my-namespace
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: "Initial"  # Or "InPlace"
```

---

<!-- Full VPA Example -->
## Full VPA Resource Example

![bg left:20%](./img/aurora.png)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app-vpa
  namespace: my-namespace
  labels:
    team: your-team-name
    environment: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: "Initial"
  resourcePolicy:
    containerPolicies:
      - containerName: "*"
        minAllowed:
          cpu: 50m
          memory: 64Mi
        maxAllowed:
          cpu: 500m
          memory: 512Mi
        controlledResources: ["cpu", "memory"]
```

---

<!-- VPA + HPA Integration -->
## VPA + HPA: Best Practice Pattern

![bg left:20%](./img/aurora.png)

### The Division of Responsibility:
- **HPA** → Scales replicas (how many pods)
- **VPA** → Scales resources (how much per pod)

### Critical: Use `controlledResources`

```yaml
# HPA manages CPU scaling (replicas)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

# VPA manages ONLY memory (avoid conflict)
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
spec:
  resourcePolicy:
    containerPolicies:
      - containerName: "*"
        controlledResources: ["memory"]
```

---

<!-- Production Guardrails -->
## Production Guardrails

![bg left:20%](./img/aurora.png)

### DO NOT:

1. **Use Auto mode** - Deprecated
2. **Combine VPA with HPA on same resources** - Conflict inevitable
3. **Enable VPA for batch jobs** - Use KEDA Jobs instead
4. **Set minReplicaCount < 2 with Recreate** - Updater defaults to 2

### DO:

1. **Use Initial or InPlace mode** - Minimize disruption
2. **Set controlledResources** - Avoid HPA/VPA conflicts
3. **Monitor recommendations** - Check VPA status weekly
4. **Use resource policy limits** - Define min/max bounds

---

<!-- Common Problems -->
## Troubleshooting: Common Issues

![bg left:20%](./img/aurora.png)

### Problem: VPA not generating recommendations
```bash
# Check Metrics Server
kubectl top nodes
kubectl top pods -n my-namespace

# Check VPA recommender logs
kubectl logs -n vpa-system deployment/vpa-recommender
```

### Problem: Recommendations not applied
```bash
# Check VPA components running
kubectl get pods -n vpa-system

# Check admission controller
kubectl logs -n vpa-system deployment/vpa-admission-controller
```

### Problem: Pods being evicted
```bash
# Check VPA mode
kubectl get vpa my-app-vpa -o yaml

# Consider switching to InPlace or Initial mode
```

---

<!-- Validation Checklist -->
## Validation Checklist

![bg left:20%](./img/aurora.png)

### 1. Verify VPA Components
```bash
kubectl get pods -n vpa-system
# Should show: recommender, updater, admission-controller all Running
```

### 2. Verify Metrics Server
```bash
kubectl top nodes
# Should show node CPU/memory usage
```

### 3. Check VPA Recommendations
```bash
kubectl describe vpa my-app-vpa
# Look for: recommendedContainerResources
```

### 4. Test Pod Creation
```bash
# Create deployment with VPA
kubectl create deployment test-vpa --image=nginx

# Add VPA, create new pod
kubectl rollout restart deployment/test-vpa

# Check resource requests were applied
kubectl describe pod -l app=test-vpa
```

---

<!-- Implementation Plan -->
## Implementation Plan

![bg left:20%](./img/aurora.png)

### Phase 1: Validation in DEV (Weeks 1-2)
- Deploy VPA to Zone DEV
- Apply baseline policies to test workloads
- Monitor recommendations and overhead
- Document findings

### Phase 2: Production Readiness (Weeks 3-4)
- Define SLOs for recommendation accuracy
- Create documentation and runbooks
- Create Terraform module for aurora-platform-charts
- Integrate with cluster provisioning

### Phase 3: Automation & Handover (Weeks 5-6)
- CI/CD pipeline for VPA policy updates
- Alerting on VPA issues
- Training and documentation
- Organization-wide rollout

---

<!-- Next Steps -->
## Next Steps and Open Questions

![bg left:20%](./img/aurora.png)

### Immediate Actions:
1. **Review and approve** this presentation and documentation
2. **Deploy VPA to DEV** for testing with your workloads
3. **Share feedback** on recommended practices

### Questions for Investigation:
- Typical recommendation accuracy over time?
- How recommendations change with workload patterns?
- Optimal VPA update frequency?

---

<!-- Conclusion -->
## Conclusion

![bg left:20%](./img/aurora.png)

- **What:** VPA is a Kubernetes-native tool for right-sizing container resources
- **Why:** Reduces waste, improves cluster efficiency, complements HPA
- **How:** Recommender analyzes, Updater applies, Admission controller enforces
- **Next Step:** Deploy to DEV, validate with workloads, share findings

<blockquote>
Right-size your resources, optimize your cluster, reduce costs.
</blockquote>

---

<!-- References -->
## References

![bg left:20%](./img/aurora.png)

### VPA Documentation:
1. <a href="https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/README.md">VPA GitHub Repository</a>
2. <a href="https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/">Kubernetes Horizontal Pod Autoscaling</a>
3. <a href="https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/">Kubernetes Resource Management</a>

### Aurora Platform:
4. <a href="https://github.com/gccloudone-aurora/aurora-platform-charts">Aurora Platform Charts</a>
5. VPA Implementation Issue #473
6. VPA Documentation Epic #488

---

<!-- Appendix -->
## Appendix: VPA Modes Detail

![bg left:20%](./img/aurora.png)

### Update Mode Comparison:

| Mode | Updates | Evicts | Pod Disruption | Use Case |
|------|---------|--------|----------------|----------|
| Off | No | No | None | Analysis only |
| Initial | No | No | None | Production-safe |
| InPlace | Yes | No | Minimal | Production-safe |
| InPlaceOrRecreate | Yes | Yes (fallback) | Some | Dev/testing |
| Recreate | Yes | Yes | High | Last resort |
| Auto | Deprecated | Deprecated | N/A | Do not use |

### When to Use Each:

- **Initial:** Production, workloads with frequent restarts
- **InPlace:** Production, workloads where disruption must be avoided
- **InPlaceOrRecreate:** Dev/testing, when you need updates quickly
- **Recreate:** Emergency, when other modes fail

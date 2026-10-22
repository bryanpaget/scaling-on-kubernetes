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

A: Kubernetes native controls always win. Karpenter strictly respects Pod Disruption Budgets. If a consolidation or spot replacement violates your Pod Disruption Budget, Karpenter aborts the move. For critical workloads, we can inject `karpenter.sh/do-not-disrupt: "true"` to lock pods to their current node permanently.

---

**Q: What's the blast radius / rollback story if VPA recommends something terrible in Initial or InPlace mode?**

A: The blast radius is tightly constrained. We enforce safety rails using VPA `minAllowed` and `maxAllowed` limits so rogue recommendations can never starve or balloon a pod. If a bad update goes live, rollback is instant: delete the VPA object or change its mode to Off, and manually hardcode the last-known-stable resource requests in your deployment manifest.

---

**Q: Scale-to-zero cold starts — how bad, and how do I mitigate (keep-warm, min replicas)?**

A: The cold start is real—typically 1-3 minutes if Karpenter must provision a raw node from scratch. We mitigate based on application tier: Tier-1 customer-facing apps are barred from scaling to zero (`minReplicas: 1`). For async workers, we accept the delay or use Karpenter headroom to keep small buffers of empty, pre-warmed capacity ready.

---

<!-- References -->
## References

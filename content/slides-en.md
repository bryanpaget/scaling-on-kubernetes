## The point

![bg left:20%](./img/aurora.png)

Aurora should learn Karpenter properly and keep a small reference implementation that it runs and understands itself.

This is not an argument for self-hosting Karpenter everywhere. In some places Aurora will have no choice but to run it directly, and in others a cloud provider offers a managed version that is really Karpenter underneath.

The reference implementation is what lets Aurora tell those cases apart and judge a managed service on evidence rather than on the vendor's word.

---

## Why it matters

![bg left:20%](./img/aurora.png)

**The first reason:** Some platforms leave no alternative. On-prem, and any cloud without a managed Karpenter offering, mean that if Aurora wants Karpenter's just-in-time provisioning and consolidation, it has to run Karpenter itself.

**The second reason:** Other platforms hand Aurora a managed version for free. Azure Node Auto Provisioning (NAP) is Microsoft's managed, Karpenter-based autoscaler for AKS, and AWS offers a comparable path in EKS Auto Mode.

**The third reason:** A managed service is only a good deal if it behaves the way it should, and Aurora cannot assess that from the outside.

---

## What Aurora should do

![bg left:20%](./img/aurora.png)

1. **Start:** Learn Karpenter and stand up a small self-hosted reference on a non-production Azure (AKS) cluster.

2. **Compare:** Try Azure NAP on a separate non-production cluster and compare the two directly.

3. **Decide:** If NAP measures up, use it. If it falls short, run self-hosted Karpenter on Azure instead.

The same expertise carries over to on-prem (where self-hosting is the only option) and to other clouds as their autoscaling stories mature.

---

## What this is not

![bg left:20%](./img/aurora.png)

- This proposal does not commit Aurora to self-hosting Karpenter everywhere.
- It does not put Karpenter into production before the Azure comparison is done.
- It does not settle the choice for AWS, GKE, or on-prem. Those come later, and they get to reuse whatever Aurora learns on Azure.

---

## Current state

![bg left:20%](./img/aurora.png)

- Aurora runs on Azure (AKS) today and uses Cluster Autoscaler for node scaling.
- AWS is supported in the platform chart, while GKE and on-prem remain architectural direction rather than running systems.
- Moving off Cluster Autoscaler to a workload-aware autoscaler, whether NAP or Karpenter, is on the compute-efficiency roadmap (Stage 2 item B).
- The choice between the two is still open.

**One practical check first:** Aurora's AKS clusters use managed Cilium. Before any trial, confirm whether NAP supports that configuration.

---

## One caution

![bg left:20%](./img/aurora.png)

An autoscaler decides when to add capacity and what shape that capacity should take. It does not make a cold node start any faster.

A freshly provisioned node still has to boot and pull images whether it was requested by Cluster Autoscaler, self-hosted Karpenter, or NAP.

If Aurora needs warm headroom to absorb bursts, that is a separate piece of work (a small warm pool or low-priority filler pods), and not a reason to prefer one autoscaler over another.

The trial should keep that line clear when measuring startup time, so the comparison stays honest.

---

## References

![bg left:20%](./img/aurora.png)

- Compute-efficiency roadmap (Stage 2 item B): ../../roadmap/roadmap.md
- Karpenter: https://karpenter.sh/docs/
- Azure Karpenter provider and NAP comparison: https://github.com/Azure/karpenter-provider-azure
- AKS Node Auto Provisioning: https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning
- AWS EKS Auto Mode: https://docs.aws.amazon.com/eks/latest/best-practices/automode.html

[English](#english) | [Français](#français)
<a id="english"></a>

# Aurora Karpenter Learning and Azure Evaluation Proposal

## Building Karpenter as a cross-platform reference, starting with an Azure evaluation

**Date:** 2026-10-06  
**Author:** Bryan Paget, Aurora Platform Team  
**Version:** v1.2 - Draft

---

## About This Repository

This repository contains the source for a bilingual (English/French) presentation, "Aurora Karpenter Learning and Azure Evaluation Proposal" - a platform-team guide to evaluating Karpenter for Aurora's node autoscaling needs on Azure, AWS, GKE, and on-prem environments. It builds presentation slides (via [Marp](https://marp.app/)) and publishes the slides as HTML to GitHub Pages from the `docs/` folder.

| Path | Description |
|------|-------------|
| `content/slides-en.md` | English Marp presentation source |
| `content/slides-fr.md` | French Marp presentation source |
| `config/header-en.md` | English Marp theme and front-matter (title slide) |
| `config/header-fr.md` | French Marp theme and front-matter (title slide) |
| `config/landing.html` | GitHub Pages landing page (copied to `docs/index.html`) |
| `postprocess.mjs` | Injects the aurora theme and code sizing into the Marp CLI output; run by `make html` |
| `BUILD.md` | Build architecture and fork/re-theme guide |
| `img/` | Slide images |
| `docs/` | Generated GitHub Pages site (built via `make html`, committed) |
| `.github/workflows/` | CI (build) and release workflows |

> **Build details:** See [`BUILD.md`](BUILD.md) for how the build works, why it uses
> the Marp CLI plus a post-processor (`postprocess.mjs`), where the theme lives, and a step-by-step
> guide to forking this repo into a new topic.

**View the slides online:** <https://github.com/gccloudone-aurora/vpa-presentation/>

### Build Locally

```bash
make pdf       # EN + FR presentation PDFs (requires marp CLI + Chromium)
make html      # GitHub Pages site into docs/
make preview-en / preview-fr   # live slide preview on localhost
```

> **Note on deployments:** GitHub Pages serves the committed `docs/` folder (repo **Settings → Pages → Source → "Deploy from a branch" → branch `main`, folder `/docs`**). After editing slides, run `make html` and commit the regenerated `docs/`; the site updates on push. Tagging a release with `v*` builds the PDFs and attaches them to a GitHub Release.

---

## Executive Summary

Aurora currently runs Kubernetes Cluster Autoscaler for node autoscaling on production clusters. Karpenter's model is now appearing across AWS, Azure, and other platforms, both self-hosted and inside managed services (AKS NAP, EKS Auto Mode). The platform team needs working Karpenter knowledge regardless of which option each platform ultimately selects.

This proposal recommends a time-boxed, non-production evaluation on Azure that produces two things:

1. **A platform-independent reference and method:** NodePool design, disruption and consolidation behavior, observability, runbooks, and a repeatable evaluation approach that Aurora owns.

2. **An evidence-based Azure recommendation** among three options: remain on Cluster Autoscaler, adopt AKS Node Auto Provisioning (NAP), or adopt self-hosted Karpenter.

This is not a production adoption decision and does not select an autoscaler for AWS, GKE, or on-prem. Those are assessed separately, reusing the method developed here (see [Platform status](#platform-status)).

**Key takeaway:** Aurora needs a Karpenter reference it owns, because Karpenter-based options are emerging across platforms. A time-boxed Azure evaluation builds that reference, produces a reusable method, and gives Azure an evidence-based answer, while staying honest about what will not transfer to other platforms.

---

## Table of Contents

**The Proposal**
1. [Executive Summary](#executive-summary)
2. [Problem and Scope](#problem-and-scope)
3. [Why Aurora Needs a Karpenter Reference](#why-aurora-needs-a-karpenter-reference)
4. [Platform Status](#platform-status)
5. [Recommendation](#recommendation)
6. [Evaluation Design](#evaluation-design)
7. [Timeline, Effort, and Ownership](#timeline-effort-and-ownership)
8. [Expected Deliverables](#expected-deliverables)
9. [Conclusion](#conclusion)

**Technical Details**
10. [How Node Autoscaling Works](#how-node-autoscaling-works)
11. [Karpenter vs Cluster Autoscaler](#karpenter-vs-cluster-autoscaler)
12. [NodePool as Source of Truth](#nodepool-as-source-of-truth)
13. [Why Self-Hosted Karpenter When Possible](#why-self-hosted-karpenter-when-possible)
14. [Risks and Mitigations](#risks-and-mitigations)
15. [Startup versus Autoscaler Behavior](#startup-versus-autoscaler-behavior)

---

## Problem and Scope

Aurora currently uses Kubernetes Cluster Autoscaler. The platform team is evaluating workload-aware node provisioning and consolidation to improve utilization, reduce manual node-pool planning, and support future right-sizing work.

The gap is experience: Aurora cannot yet judge whether Karpenter-based options, managed or self-hosted, meet its operational and compliance requirements on any platform, and it has no owned reference implementation to judge them against.

**This proposal covers:**

- Karpenter concepts, APIs, operational behavior, and failure modes
- A self-hosted Karpenter reference implementation on Azure
- An AKS NAP pilot
- A three-way comparison against the Cluster Autoscaler baseline
- A repeatable evaluation method and exit decision

**This proposal does not decide:**

- A single autoscaler for AWS, Azure, GKE, and on-prem
- Adoption of a third-party Karpenter provider on GKE
- Production migration of any Aurora cluster
- Cost savings before Aurora has baseline measurements

---

## Why Aurora Needs a Karpenter Reference

AKS NAP and EKS Auto Mode are Karpenter-based managed services, self-hosted Karpenter is available on AWS and Azure, and community providers exist for other platforms. Whatever Aurora decides per cloud, the team will need to understand NodePools, consolidation, drift, and the failure modes of just-in-time provisioning. Owning a reference implementation is what makes that understanding real rather than theoretical.

- **One source of truth.** A self-hosted reference defines how Aurora expects node autoscaling to behave. Every managed option can then be measured against it rather than against vendor marketing.
- **On-prem has no managed option.** Off-cloud, there is no NAP or EKS Auto Mode. If Aurora wants Karpenter-style provisioning on-prem, it must run Karpenter itself, so the expertise is not optional there.
- **Managed options still have to be operated.** Troubleshooting NAP or EKS Auto Mode requires knowing what the underlying controller is doing.
- **Each platform has a different decision.** Azure and AWS offer managed and self-hosted routes, GKE has a native alternative (GKE NAP and ComputeClasses), and on-prem depends on provider maturity. Informed choices on each need shared baseline knowledge.
- **Exit paths must be real.** If a managed service falls behind, restricts a feature, or stops fitting, the team needs the skills to self-host.

### What transfers, and what does not

| Transfers across platforms | Does not transfer |
|----------------------------|-------------------|
| NodePool constraints, limits, capacity-type logic | NodeClass definitions (provider-specific) |
| Disruption budgets, consolidation, drift behavior | Node images, boot path, image-patching mechanics |
| Interaction with PDBs, VPA, KEDA, scale-to-zero | Cloud identity, permissions, quota management |
| Metrics, alerting, troubleshooting approach | Instance/SKU availability and regional constraints |
| Evaluation method and acceptance criteria | Managed-service support boundaries and release cadence |

The right-hand column is where much of the operational risk lives. Azure results must not be assumed to apply to other platforms.

---

## Platform Status

| Platform | Status today | Status in this proposal | Next step |
|----------|--------------|-------------------------|-----------|
| **Azure (AKS)** | In production; current provider | In scope: self-hosted reference plus AKS NAP pilot | Decision by [date] |
| **AWS** | Supported in the platform chart; no known running clusters | Out of scope; self-hosted Karpenter and EKS Auto Mode are separate options | Evaluate by [date], reusing this method |
| **GKE** | Architectural direction; not deployed | Out of scope; no Google-managed Karpenter. A community provider would be a separate security and support decision, with GKE NAP and ComputeClasses as the native alternative | Risk assessment by [date] |
| **On-prem** | Architectural direction; not deployed | Out of scope; depends on Cluster API provider maturity. No managed option exists, so a self-hosted reference matters most here | Revisit by [date] |

Azure goes first because it is Aurora's production platform today, a managed Karpenter option (NAP) exists there, and a first-party self-hosted provider is available for the reference implementation.

> **Terminology:** **AKS NAP** (Azure, Karpenter-based) and **GKE NAP** (Google, a different product) are not the same thing. This document uses the prefixed names throughout.

---

## Recommendation

### 0. Check eligibility first

Before building anything, confirm that Aurora's AKS clusters can use AKS NAP. Aurora's clusters use AKS managed Cilium CNI, so the networking and dataplane requirements for NAP must be checked specifically against that configuration, along with cluster-configuration and feature requirements and any incompatibility with Cluster Autoscaler on the same cluster. Review current Microsoft documentation. If NAP is not viable for Aurora's cluster configuration, the pilot narrows to self-hosted Karpenter versus Cluster Autoscaler, and this should be known before effort is spent.

### 1. Build a self-hosted Azure reference implementation

Deploy self-hosted Karpenter using the Azure provider on a separate non-production AKS cluster. It should be small enough to operate safely and complete enough to teach the team to:

- Define NodePools and provider-specific NodeClasses
- Configure workload constraints, capacity types, limits, and disruption policies
- Observe provisioning, consolidation, replacement, and failure behavior
- Manage cloud identity, quotas, upgrades, rollback, and emergency capacity
- Integrate metrics, logs, alerts, and cost reporting

The reference implementation is Aurora's source of truth and control group. It is a learning tool, not automatically the production target.

### 2. Pilot AKS NAP

Pilot AKS NAP on a separate non-production AKS cluster. NAP is Microsoft-managed and Karpenter-based. It uses Karpenter concepts and resources, but Microsoft controls the managed components, release schedule, lifecycle operations, and Azure integrations. Test NAP as an Azure service; do not assume equivalence with the self-hosted implementation.

### 3. Compare three options

Compare **Cluster Autoscaler (baseline)**, **self-hosted Karpenter**, and **AKS NAP** using identical workload profiles. Never run two autoscalers against the same cluster or workload. Use separate non-production clusters, controlled test windows, or another design that prevents controller interference.

The comparison should answer:

- Does each option provision required capacity reliably?
- Does it meet Aurora's scale-up and scheduling latency targets?
- Does consolidation respect workload disruption tolerances and PDBs?
- Are labels, taints, images, identities, zones, SKUs, and capacity types configurable enough?
- Do metrics, logs, events, and failure signals reach Aurora's observability stack?
- Can Aurora diagnose incidents without depending entirely on vendor support?
- Are upgrade timing, node image patching, support boundaries, and rollback acceptable?
- Does operational and infrastructure cost justify the approach?

### 4. Make an evidence-based Azure decision

- **Adopt AKS NAP** if it meets the acceptance criteria and its managed-service trade-offs are acceptable. It is managed Karpenter, so this is the pragmatic default where it fits.
- **Adopt self-hosted Karpenter** if NAP has material capability, control, observability, support, portability, or compliance gaps and Karpenter meets the criteria.
- **Remain on Cluster Autoscaler** if neither Karpenter option demonstrates sufficient benefit over the baseline.

Record the outcome in a separate decision record once evidence is available.

---

## Evaluation Design

### Baseline (Cluster Autoscaler)

Record current behavior before changing the test environment:

- Pod pending-to-scheduled latency
- Node provisioning and readiness latency
- Image-pull time after node readiness
- Node utilization and requested capacity
- Scale-down and disruption behavior
- Infrastructure cost per test window
- Failure, quota, and scheduling events

### Test cases

1. A stateless service with predictable demand
2. A bursty workload that creates pending pods
3. A workload with strict taints, tolerations, affinity, or topology requirements
4. A workload protected by a PDB
5. A workload with large images or slow startup hooks
6. A workload that exercises scale-down and consolidation
7. **A KEDA-scaled workload**, including scale-to-zero and scale-up from zero with consolidation active
8. **A VPA-managed workload**, where requests change after initial scheduling and node packing must adapt
9. **A workload with zonal storage** (persistent volumes with zone affinity) and DaemonSet overhead
10. **Node lifecycle events:** image patching, drift, node expiry (`expireAfter`), and maintenance windows

KEDA and VPA are planned Aurora capabilities, not yet enabled in the platform chart, but cases 7 and 8 reflect how Aurora intends to scale workloads (see the compute-efficiency roadmap) and are where node autoscalers are most stressed. Include them so the evaluation covers the target state, not just today's.

### Acceptance criteria

Thresholds must be set **before testing begins** so results are not interpreted after the fact. Suggested starting points are in brackets; Aurora should replace them with agreed values.

| Area | Evidence required | Threshold |
|------|-------------------|-----------|
| Provisioning | Nodes become available for all supported workload constraints | [>= 99% of scale-up events succeed] |
| Latency | Pending-to-ready under defined load | [p95 <= X seconds, including image pull] |
| Consolidation | Capacity reduced without disruption beyond PDB limits | [zero PDB violations across N consolidation events] |
| Configuration | Required labels, taints, images, identities, zones, SKUs, capacity types supported | [all items on the required list] |
| Observability | Metrics, events, logs support diagnosis and alerting | [all defined alerts fire in fault-injection tests] |
| Operations | Upgrade, rollback, quota, incident, emergency-capacity, and image-patching procedures documented and tested | [each procedure executed once successfully] |
| Security | See below | [per Aurora PBMM review] |
| Economics | Cost and utilization measured against the Cluster Autoscaler baseline, without relying on external percentage claims | [target improvement, if any, agreed up front] |

**Security criteria differ by option.** For self-hosted Karpenter, the question is whether Aurora can configure controller identity and node-provisioning permissions to least privilege. For AKS NAP, the question is whether Aurora can audit and accept what Microsoft's managed controller is permitted to do, including data handling, access boundaries, and support access. These are different tests and should be assessed separately against PBMM requirements.

---

## Timeline, Effort, and Ownership

| Item | Value |
|------|-------|
| Total duration | [e.g., 10-12 weeks, time-boxed] |
| Team and allocation | [names/roles, % allocation] |
| Estimated infrastructure cost | [non-production cluster and test-load cost] |
| Decision date | [date] |

---

## Expected Deliverables

- Version-controlled self-hosted Karpenter reference configuration (Aurora's source of truth)
- AKS NAP pilot configuration and operating notes
- Baseline and three-way comparison measurements
- Dashboards, alerts, and troubleshooting runbooks
- Documented upgrade, rollback, image-patching, and exit procedures
- A reusable evaluation method for the other platforms
- Azure recommendation supported by pilot evidence

---

## Conclusion

Aurora needs a Karpenter reference it owns, because Karpenter-based options are emerging across Azure, AWS, and elsewhere, and because on-prem will have no managed alternative. A time-boxed Azure evaluation builds that reference, produces a reusable method, and gives Azure an evidence-based answer, while staying honest about what will not transfer to other platforms. Aurora stays adaptable: where a cloud offers managed Karpenter such as Azure NAP, it is worth trying, precisely because the team will understand what sits underneath. The result may be AKS NAP, self-hosted Karpenter, or staying on Cluster Autoscaler; in each case Aurora will understand why.

---

## References

- Karpenter documentation: https://karpenter.sh/docs/
- Karpenter concepts: https://karpenter.sh/docs/concepts/
- Karpenter upstream: https://github.com/kubernetes-sigs/karpenter
- Azure Karpenter provider and NAP comparison: https://github.com/Azure/karpenter-provider-azure
- AKS Node Auto Provisioning: https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning
- AWS EKS Auto Mode: https://docs.aws.amazon.com/eks/latest/best-practices/automode.html
- GKE Node Auto-Provisioning: https://cloud.google.com/kubernetes-engine/docs/concepts/node-auto-provisioning
- GKE ComputeClasses: https://cloud.google.com/kubernetes-engine/docs/concepts/about-custom-compute-classes

---

<a id="français"></a>

# Proposition d'apprentissage Karpenter et évaluation Azure

## Construire Karpenter comme référence inter-plateforme, en commençant par l'évaluation Azure

**Date :** 2026-10-06  
**Auteur :** Bryan Paget, Équipe Aurora Platform  
**Version :** v1.2 - Ébauche

---

## À propos de ce dépôt

Ce dépôt contient la source d'une présentation bilingue (anglais/français), « Proposition d'apprentissage Karpenter et évaluation Azure » - un guide pour l'équipe plateforme sur l'évaluation de Karpenter pour les besoins d'autoscaling de nœuds d'Aurora sur Azure, AWS, GKE et environnements on-prem. Il génère des diapositives de présentation (via [Marp](https://marp.app/)) et publie les diapositives en tant que HTML sur GitHub Pages à partir du dossier `docs/`.

| chemin | description |
|--------|-------------|
| `content/slides-en.md` | Source de la présentation Marp en anglais |
| `content/slides-fr.md` | Source de la présentation Marp en français |
| `config/header-en.md` | Thème Marp et front-matter en anglais (diapositive titre) |
| `config/header-fr.md` | Thème Marp et front-matter en français (diapositive titre) |
| `config/landing.html` | Page d'accueil GitHub Pages (copiée dans `docs/index.html`) |
| `postprocess.mjs` | Injecte le thème aurora et le dimensionnement du code dans la sortie du CLI Marp; exécuté par `make html` |
| `BUILD.md` | Guide d'architecture du build et de fork/re-theme |
| `img/` | Images des diapositives |
| `docs/` | Site GitHub Pages généré (construit via `make html`, commit) |
| `.github/workflows/` | CI (build) et workflows de release |

> **Détails du build :** Voir [`BUILD.md`](BUILD.md) pour le fonctionnement du build,
> pourquoi il utilise le CLI Marp plus un post-processeur (`postprocess.mjs`), où se trouve le thème,
> et un guide étape par étape pour forker ce dépôt vers un nouveau sujet.

**Voir les diapositives en ligne :** <https://github.com/gccloudone-aurora/vpa-presentation/>

### Construire localement

```bash
make pdf       # PDF de présentation EN + FR (nécessite marp CLI + Chromium)
make html      # Site GitHub Pages dans docs/
make preview-en / preview-fr   # prévisualisation en direct des diapositives sur localhost
```

> **Note sur les déploiements :** GitHub Pages sert le dossier `docs/` commit (dépôt **Settings → Pages → Source → "Deploy from a branch" → branche `main`, dossier `/docs`**). Après avoir modifié les diapositives, exécutez `make html` et committez les `docs/` régénérés ; le site se met à jour à la push. Taguer une release avec `v*` construit les PDFs et les attache à une Release GitHub.

---

## Résumé exécutif

Aurora exécute actuellement Cluster Autoscaler pour le dimensionnement des nœuds sur les clusters de production. Le modèle de Karpenter apparaît maintenant sur AWS, Azure et d'autres plateformes, à la fois auto-hébergé et dans les services gérés (AKS NAP, EKS Auto Mode). L'équipe plateforme a besoin d'une expertise Karpenter fonctionnelle quel que soit l'option que chaque plateforme choisira finalement.

Cette proposition recommande une évaluation time-boxée, non-production sur Azure qui produit deux choses :

1. **Une référence et méthode indépendantes de la plateforme :** conception NodePool, comportement de disruption et consolidation, observabilité, runbooks, et une approche d'évaluation répétable que Aurora possède.

2. **Une recommandation Azure fondée sur des preuves** parmi trois options : rester sur Cluster Autoscaler, adopter AKS Node Auto Provisioning (NAP), ou adopter Karpenter auto-hébergé.

 Ceci n'est pas une décision d'adoption production et ne choisit pas un autoscaler pour AWS, GKE, ou on-prem. Ceux-ci sont évalués séparément, en réutilisant la méthode développée ici (voir [Statut des plateformes](#statut-des-plateformes)).

**Message clé :** Aurora a besoin d'une référence Karpenter qu'elle possède, parce que les options basées sur Karpenter émergent sur plusieurs plateformes. Une évaluation Azure time-boxée construit cette référence, produit une méthode réutilisable, et donne à Azure une réponse fondée sur des preuves, tout en restant honnête sur ce qui ne se transférera pas aux autres plateformes.

---

## Table des matières

**La proposition**
1. [Résumé exécutif](#résumé-exécutif)
2. [Problème et portée](#problème-et-portée)
3. [Pourquoi Aurora a besoin d'une référence Karpenter](#pourquoi-aurora-a-besoin-dune-référence-karpenter)
4. [Statut des plateformes](#statut-des-plateformes)
5. [Recommandation](#recommandation)
6. [Conception de l'évaluation](#conception-de-lévaluation)
7. [Calendrier, effort, et propriété](#calendrier-effort-et-propriété)
8. [Livrables attendus](#livrables-attendus)
9. [Conclusion](#conclusion)

**Détails techniques**
10. [Comment fonctionne le dimensionnement de nœuds](#comment-fonctionne-le-dimensionnement-de-nœuds)
11. [Karpenter versus Cluster Autoscaler](#karpenter-versus-cluster-autoscaler)
12. [NodePool comme source de vérité](#nodepool-comme-source-de-vérité)
13. [Pourquoi auto-héberger Karpenter quand possible](#pourquoi-auto-héberger-karpenter-quand-possible)
14. [Risques et atténuations](#risques-et-atténuations)
15. [Démarrage versus comportement d'autoscaler](#démarrage-versus-comportement-dautoscaler)

---

## Problème et portée

Aurora utilise actuellement Cluster Autoscaler pour Kubernetes. L'équipe plateforme évalue le provisionnement de nœuds conscient des workloads et la consolidation pour améliorer l'utilisation, réduire la planification manuelle de pools de nœuds, et supporter le dimensionnement vertical futur.

Le manque est l'expérience : Aurora ne peut pas encore juger si les options Karpenter, gérées ou auto-hébergées, répondent à ses exigences opérationnelles et de conformité sur n'importe quelle plateforme, et elle n'a aucune implémentation de référence qu'elle possède pour les juger.

**Cette proposition couvre :**

- Concepts, APIs, comportement opérationnel, et modes d'échec Karpenter
- Une implémentation de référence Karpenter auto-hébergée sur Azure
- Un pilote AKS NAP
- Une comparaison trois-voies contre Cluster Autoscaler
- Une méthode d'évaluation répétable et une décision de sortie

**Cette proposition ne décide pas :**

- Un autoscaler unique pour AWS, Azure, GKE, et on-prem
- L'adoption d'un fournisseur Karpenter tiers sur GKE
- La migration production de n'importe quel cluster Aurora
- Les économies avant qu'Aurora n'ait des mesures de baseline

---

## Pourquoi Aurora a besoin d'une référence Karpenter

AKS NAP et EKS Auto Mode sont des services gérés basés sur Karpenter, Karpenter auto-hébergé est disponible sur AWS et Azure, et des fournisseurs communautaires existent pour d'autres plateformes. Quelle que soit la décision d'Aurora par cloud, l'équipe devra comprendre NodePools, consolidation, drift, et les modes d'échec du provisionnement juste-à-temps. Posséder une implémentation de référence est ce qui rend cette compréhension réelle plutôt que théorique.

- **Une source de vérité.** Une référence auto-hébergée définit comment Aurora s'attend au comportement du dimensionnement des nœuds. Chaque option gérée peut alors être mesurée contre elle plutôt que contre le marketing du fournisseur.
- **On-prem n'a pas d'option gérée.** Hors-cloud, il n'y a pas de NAP ou EKS Auto Mode. Si Aurora veut le provisionnement style Karpenter on-prem, elle doit exécuter Karpenter elle-même, donc l'expertise n'est pas optionnelle là-bas.
- **Les options gérées doivent toujours être opérées.** Le dépannage de NAP ou EKS Auto Mode nécessite de connaître ce que le contrôleur sous-jacent fait.
- **Chaque plateforme a une décision différente.** Azure et AWS offrent des routes gérées et auto-hébergées, GKE a une alternative native (GKE NAP et ComputeClasses), et on-prem dépend de la maturité du fournisseur. Des choix éclairés sur chaque besoin de connaissances de base partagées.
- **Les chemins de sortie doivent être réels.** Si un service géré tombe en retard, restreint une fonctionnalité, ou cesse de convenir, l'équipe a besoin des compétences pour s'auto-héberger.

### Ce qui se transfère, et ce qui ne se transfère pas

| Se transfère entre plateformes | Ne se transfère pas |
|--------------------------------|---------------------|
| Contraintes, limites, logique type-capacité NodePool | Définitions NodeClass (spécifiques au fournisseur) |
| Budgets de disruption, consolidation, comportement drift | Images de nœud, chemin de démarrage, mécanique de patch d'image |
| Interaction avec PDBs, VPA, KEDA, descente à zéro | Identité cloud, permissions, gestion de quota |
| Approche métriques, alertes, dépannage | Disponibilité SKU et contraintes régionales |
| Méthode d'évaluation et critères d'acceptation | Limites de support service géré et cadence de publication |

La colonne de droite est où réside une grande partie du risque opérationnel. Les résultats Azure ne doivent pas être supposés s'appliquer aux autres plateformes.

---

## Statut des plateformes

| Plateforme | Statut actuel | Dans cette proposition | Prochaine étape |
|------------|---------------|------------------------|-----------------|
| **Azure (AKS)** | En production ; fournisseur actuel | En portée : référence auto-hébergée plus pilote AKS NAP | Décision par [date] |
| **AWS** | Supporté dans le chart platform ; pas de clusters connus | Hors portée ; Karpenter auto-hébergé et EKS Auto Mode sont des options séparées | Évaluer par [date], réutiliser cette méthode |
| **GKE** | Direction architecturale ; non déployé | Hors portée ; pas de Karpenter géré Google. Un fournisseur communautaire serait une décision de sécurité et de support séparée, avec GKE NAP et ComputeClasses comme alternative native | Évaluation des risques par [date] |
| **On-prem** | Direction architecturale ; non déployé | Hors portée ; dépend de la maturité du fournisseur Cluster API. Aucune option gérée n'existe, donc une référence auto-hébergée compte le plus ici | Réévaluer par [date] |

Azure va en premier parce qu'il est la plateforme de production actuelle d'Aurora, une option Karpenter gérée (NAP) existe là-bas, et un fournisseur auto-hébergé première-vérité est disponible pour la implémentation de référence.

> **Terminologie :** **AKS NAP** (Azure, basé sur Karpenter) et **GKE NAP** (Google, un produit différent) ne sont pas la même chose. Ce document utilise les noms préfixés partout.

---

## Recommandation

### 0. Vérifier l'éligibilité d'abord

Avant de construire quoi que ce soit, confirmer que les clusters AKS Aurora peuvent utiliser AKS NAP. Les clusters Aurora utilisent CNI Cilium géré AKS, donc les exigences de réseau et de dataplane pour NAP doivent être vérifiées spécifiquement contre cette configuration, avec les exigences de configuration de cluster et de fonctionnalités et toute incompatibilité avec Cluster Autoscaler sur le même cluster. Examiner la documentation Microsoft actuelle. Si NAP n'est pas viable pour la configuration du cluster Aurora, le pilote se limite à Karpenter auto-hébergé versus Cluster Autoscaler, et cela devrait être connu avant que l'effort ne soit dépensé.

### 1. Construire une implémentation de référence auto-hébergée Azure

Déployer Karpenter auto-hébergé en utilisant le fournisseur Azure sur un cluster AKS non-production séparé. Il devrait être assez petit pour être opéré en toute sécurité et assez complet pour enseigner à l'équipe :

- Définitions NodePool et NodeClasses spécifiques au fournisseur
- Configuration des contraintes de charge, types de capacité, limites et politiques de disruption
- Observation du provisionnement, consolidation, remplacement, et comportement d'échec
- Gestion de l'identité cloud, quotas, upgrades, rollback, et capacité d'urgence
- Intégration des métriques, logs, alertes, et rapport de coût

L'implémentation de référence est la source de vérité d'Aurora et le groupe contrôle. C'est un outil d'apprentissage, pas automatiquement la cible production.

### 2. Pilote AKS NAP

Pilote AKS NAP sur un cluster AKS non-production séparé. NAP est géré par Microsoft et basé sur Karpenter. Il utilise les concepts et ressources Karpenter, mais Microsoft contrôle les composants gérés, le calendrier de versions, les opérations de cycle de vie, et les intégrations Azure. Tester NAP comme un service Azure ; ne pas supposer l'équivalence avec l'implémentation auto-hébergée.

### 3. Comparer trois options

Comparer **Cluster Autoscaler (baseline)**, **Karpenter auto-hébergé**, et **AKS NAP** en utilisant des profils de charge identiques. Ne jamais exécuter deux autoscalers contre le même cluster ou workload. Utiliser des clusters non-production séparés, des fenêtres de test contrôlées, ou une autre conception qui empêche l'interférence du contrôleur.

La comparaison devrait répondre :

- Chaque option provisionne-t-elle la capacité requise de manière fiable ?
- Répond-elle aux cibles de latence de mise à l'échelle et d'ordonnancement d'Aurora ?
- La consolidation respecte-t-elle les tolérances de disruption des workloads et les PDBs ?
- Les labels, taints, images, identités, zones, SKUs, et types de capacité sont-ils suffisamment configurables ?
- Les métriques, logs, événements, et signaux d'échec atteignent-ils la pile d'observabilité d'Aurora ?
- Aurora peut-elle diagnostiquer les incidents sans entièrement dépendre du support du fournisseur ?
- Le timing des upgrades, le patching des images de nœud, les limites de support, et le rollback sont-ils acceptables ?
- Le coût opérationnel et d'infrastructure justifie-t-il l'approche ?

### 4. Prendre une décision Azure fondée sur des preuves

- **Adopter AKS NAP** s'il répond aux critères et les compromis gérés sont acceptables. C'est Karpenter géré, donc c'est le défaut pragmatique là où cela convient.
- **Adopter Karpenter auto-hébergé** si NAP a des lacunes matérielles de capacité, contrôle, observabilité, support, portabilité, ou conformité et que Karpenter répond aux critères.
- **Rester sur Cluster Autoscaler** si aucune option Karpenter ne démontre un bénéfice suffisant sur la baseline.

Enregistrer le résultat dans un enregistrement de décision séparé une fois les preuves disponibles.

---

## Conception de l'évaluation

### Baseline (Cluster Autoscaler)

Enregistrer le comportement actuel avant de changer l'environnement de test :

- Latence du pod en attente à l'ordonnancement
- Latence de provisionnement et de préparation du nœud
- Temps de tirage d'image après la préparation du nœud
- Utilisation du nœud et capacité demandée
- Comportement de réduction d'échelle et de disruption
- Coût d'infrastructure par fenêtre de test
- Événements d'échec, quota, et ordonnancement

### Cas de test

1. Un service stateless avec demande prévisible
2. Une charge bursty créant des pods en attente
3. Un workload avec taints, tolerations, affinité, ou topologie stricts
4. Un workload protégé par un PDB
5. Un workload avec grandes images ou hooks de démarrage lents
6. Un workload exerçant la réduction d'échelle et la consolidation
7. **Un workload KEDA-scaled**, y compris descente à zéro et montée à partir de zéro avec consolidation active
8. **Un workload VPA-managed**, où les demandes changent après l'ordonnancement initial et le packing de nœud doit s'adapter
9. **Un workload avec stockage zonal** (volumes persistants avec affinité zone) et overhead DaemonSet
10. **Événements de cycle de vie de nœud :** patch d'image, drift, expiration de nœud (`expireAfter`), et fenêtres de maintenance

KEDA et VPA sont des capacités planifiées d'Aurora, pas encore activées dans le chart platform, mais les cas 7 et 8 reflètent comment Aurora entend mettre à l'échelle les workloads (voir la feuille de route d'efficacité de calcul) et sont là où les autoscalers de nœud sont les plus stressés. Les inclure pour que l'évaluation couvre l'état cible, pas seulement aujourd'hui.

### Critères d'acceptation

Les seuils doivent être définis **avant le début des tests** afin que les résultats ne soient pas interprétés après coup. Les points de départ suggérés sont entre crochets ; Aurora devrait les remplacer par des valeurs convenues.

| Domaine | Preuve requise | Seuil |
|---------|----------------|-------|
| Provisionnement | Les nœuds deviennent disponibles pour toutes les contraintes de charge prises en charge | [>= 99 % des événements de mise à l'échelle réussissent] |
| Latence | Prêt-en-attente sous charge définie | [p95 <= X secondes, incluant le tirage d'image] |
| Consolidation | Capacité réduite sans disruption au-delà des limites PDB | [zéro violation PDB à travers N événements de consolidation] |
| Configuration | Labels, taints, images, identités, zones, SKUs, types de capacité pris en charge | [tous les éléments sur la liste requise] |
| Observabilité | Métriques, événements, logs supportent le dépannage et les alertes | [toutes les alertes définies déclenchent dans les tests d'injection de faute] |
| Opérations | Procédures d'upgrade, rollback, quota, incident, capacité d'urgence, et patch d'image documentées et testées | [chaque procédure exécutée une fois avec succès] |
| Sécurité | Voir ci-dessous | [selon revue PBMM d'Aurora] |
| Économies | Coût et utilisation mesurés contre la baseline Cluster Autoscaler, sans se fier aux pourcentages externes | [amélioration cible, le cas échéant, convenue à l'avance] |

**Les critères de sécurité diffèrent par option.** Pour Karpenter auto-hébergé, la question est de savoir si Aurora peut configurer l'identité du contrôleur et les permissions de provisionnement de nœud à moindre privilège. Pour AKS NAP, la question est de savoir si Aurora peut auditer et accepter ce que le contrôleur géré Microsoft est autorisé à faire, y compris la gestion des données, les limites d'accès, et l'accès de support. Ce sont des tests différents et devraient être évalués séparément contre les exigences PBMM.

---

## Calendrier, effort, et propriété

| Élément | Valeur |
|---------|--------|
| Durée totale | [ex., 10-12 semaines, time-boxed] |
| Équipe et allocation | [noms/rôles, % allocation] |
| Coût estimé d'infrastructure | [coût du cluster non-production et du test-load] |
| Date de décision | [date] |

---

## Livrables attendus

- Configuration de référence Karpenter auto-hébergée versionnée (source de vérité d'Aurora)
- Configuration du pilote AKS NAP et notes d'exploitation
- Mesures baseline et comparaison trois-voies
- Tableaux de bord, alertes, et runbooks de dépannage
- Procédures documentées d'upgrade, rollback, patch d'image, et sortie
- Méthode d'évaluation réutilisable pour les autres plateformes
- Recommandation Azure soutenue par des preuves pilotes

---

## Conclusion

Aurora a besoin d'une référence Karpenter qu'elle possède parce que les options basées sur Karpenter émergent sur Azure, AWS, et d'autres, et parce qu'on-prem n'aura pas d'alternative gérée. Une évaluation Azure time-boxée construit cette référence, produit une méthode réutilisable, et donne à Azure une réponse fondée sur des preuves, tout en restant honnête sur ce qui ne se transférera pas aux autres plateformes. Aurora reste adaptable : où un cloud offre Karpenter géré comme AKS NAP, cela vaut la peine d'essayer précisément parce que l'équipe comprendra ce qui se trouve dessous. Le résultat peut être AKS NAP, Karpenter auto-hébergé, ou rester sur Cluster Autoscaler ; dans chaque cas Aurora comprendra pourquoi.

---

## Références

- Documentation Karpenter : https://karpenter.sh/docs/
- Concepts Karpenter : https://karpenter.sh/docs/concepts/
- Karpenter upstream : https://github.com/kubernetes-sigs/karpenter
- Fournisseur Azure Karpenter et comparaison NAP : https://github.com/Azure/karpenter-provider-azure
- AKS Node Auto Provisioning : https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning
- AWS EKS Auto Mode : https://docs.aws.amazon.com/eks/latest/best-practices/automode.html
- GKE Node Auto-Provisioning : https://cloud.google.com/kubernetes-engine/docs/concepts/node-auto-provisioning
- GKE ComputeClasses : https://cloud.google.com/kubernetes-engine/docs/concepts/about-custom-compute-classes

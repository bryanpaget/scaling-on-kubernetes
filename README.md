
[English](#english) | [Français](#français)
<a id="english"></a>

# Scaling on Kubernetes

## VPA, KEDA, and Karpenter on the Aurora Platform

**Date:** 2026-10-02  
**Author:** Bryan Paget, Aurora Platform Team

---

## About This Repository

This repository contains the source for a bilingual (English/French) presentation, "Scaling on Kubernetes" - a platform-team guide to VPA, KEDA, and Karpenter on the Aurora Platform and how they interact. It builds presentation slides (via [Marp](https://marp.app/)) and publishes the slides as HTML to GitHub Pages from the `docs/` folder. (The repo is still named `vpa-presentation` for now; it may be renamed later.)

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

This presentation covers three autoscaling tools and how they work together on Aurora:

- **VPA (Vertical Pod Autoscaler):** Right-sizes resource requests per pod
- **KEDA (Kubernetes Event-driven Autoscaling):** Scales replicas on events, queues, and schedules
- **Karpenter:** Provisions nodes just-in-time based on pending pod demand

Together they form a four-layer scaling stack:
1. VPA scales *resource requests* (pod level)
2. HPA/KEDA scale *replica count* (pod level)
3. Karpenter scales *node count* (infrastructure level)
4. All layers interact - understand the conflicts and synergies

**Key takeaway:** Right-size pods (VPA), drive replica scaling from real demand signals (KEDA), and let Karpenter provision capacity on demand. The result is efficient resource use and lower costs.

---

## Table of Contents

**Part 1: VPA** - Right-sizing pod resources
1. What is VPA and why it matters (request vs replica scaling)
2. Three components: Recommender, Updater, Admission Controller
3. Modes (Initial, InPlace, Recreate) and when to use each
4. Aurora platform defaults (vpa-system namespace, 0.13.0)
5. When NOT to use VPA (spiky workloads, JVM apps, eviction-sensitive workloads)

**Part 2: KEDA** - Event- and schedule-driven scaling
6. What KEDA is (event-driven HPA, scale-to-zero)
7. Aurora's platform-native `offHoursScaling` feature
8. Manual ScaledObject configuration for events and cron
9. Production guardrails (scale-to-zero in non-prod only, avoid oscillation)

**Part 3: Karpenter** - Just-in-time node provisioning
10. What Karpenter is vs Cluster Autoscaler (per-demand vs fixed pools)
11. The Watch → Provision → Consolidate loop
12. NodePool as source of truth (multicloud: AWS/Azure/on-prem + GKE via CloudPilot)
13. Aurora's adoption plan and provider maturity notes
14. Risks and consolidation tradeoffs

**Part 4: Interactions & Anti-Patterns** - Putting them together
15. How all four axes layer: replica decisions + size decisions → node demand
16. Conflict rules: VPA + HPA/KEDA (never same resource), KEDA + your own HPA (don't), VPA + Karpenter (complementary)
17. Anti-patterns: oscillation, aggressive consolidation without PDBs, no resource bounds  

---

## Detailed Content

The full technical details for each tool, code examples, configuration patterns, and production guidelines are in the presentation slides:

- **English slides:** `content/slides-en.md`
- **French slides:** `content/slides-fr.md`

Build and view them locally with `make preview-en` or `make preview-fr`, or view the live GitHub Pages site.

### Quick Reference

| Axis | Tool | Scales | Level | When |
|------|------|--------|-------|------|
| Pod size | VPA | Resource requests | Pod | Usage history; right-sizing |
| Replica count | HPA | Count (fixed metric-driven) | Pod | CPU/memory metrics |
| Replica count | KEDA | Count (0→N event-driven) | Pod | Events, queues, schedules |
| Infrastructure | Karpenter | Node count | Cluster | Pending pods |

### Conflict Matrix

|  | HPA | KEDA | VPA | Karpenter |
|---|---|---|---|---|
| **HPA** | OK (same resource) | CONFLICT (both scale replicas) | OK (divide resources) | Complementary |
| **KEDA** | CONFLICT (both scale replicas) | OK (different scalers) | OK (divide resources) | Complementary |
| **VPA** | OK (divide resources) | OK (divide resources) | CONFLICT (same pod) | Complementary |
| **Karpenter** | Complementary | Complementary | Complementary | N/A |

---

<a id="français"></a>

# Mise à l'échelle sur Kubernetes

## VPA, KEDA et Karpenter sur la plateforme Aurora

**Date :** 2026-10-02  
**Auteur :** Bryan Paget, Équipe Aurora Platform

---

## À propos de ce dépôt

Ce dépôt contient la source d'une présentation bilingue (anglais/français), « Mise à l'échelle sur Kubernetes » - un guide pour l'équipe plateforme sur VPA, KEDA et Karpenter sur la plateforme Aurora et leurs interactions. Il génère des diapositives de présentation (via [Marp](https://marp.app/)) et publie les diapositives en tant que HTML sur GitHub Pages à partir du dossier `docs/`. (Le dépôt s'appelle encore `vpa-presentation` pour l'instant ; il pourra être renommé plus tard.)

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

**Recommandation :** Adopter VPA comme solution de dimensionnement vertical complémentaire à HPA pour le dimensionnement horizontal sur Aurora.

**Quoi :** VPA ajuste automatiquement les demandes de ressources CPU et mémoire *requests* pour vos conteneurs selon les modèles d'utilisation réels. Contrairement à HPA qui met à l'échelle le nombre de réplicas, VPA dimensionne correctement les demandes/limites de ressources des conteneurs individuels.

**Pourquoi maintenant :** L'optimisation des ressources est critique pour l'efficacité du cluster et la gestion des coûts. VPA élimine les suppositions manuelles sur les ressources et garantit une allocation optimale des ressources.

**Risque :** Faible. VPA est déjà déployé sur la plateforme Aurora (via le chart aurora-core). Le contrôleur d'admission garantit une création de pod安全 avec des demandes de ressources appropriées.

**Coût :** Minimal. VPA s'exécute en tant que composants système (recommandeur, updateur, contrôleur d'admission) avec moins de 1% de surcharge sur le plan de contrôle.

**Demande :** Approuver le modèle d'implémentation VPA documenté dans cette présentation et le déployer dans DEV de la Zone pour validation avec vos workloads.

**Prochaines étapes :** Examinez cette présentation, déployez VPA dans DEV, validez avec vos workloads, et partagez les résultats avec l'équipe.

---

## Table des matières

1. [Qu'est-ce que VPA?](#10-quest-ce-que-vpa)  
2. [VPA vs HPA: Deux côtés du dimensionnement](#20-vpa-vs-hpa-deux-côtés-du-dimensionnement)  
3. [Pourquoi VPA est important](#30-pourquoi-vpa-est-important)  
4. [Modes VPA et modèles recommandés pour la production](#40-modes-vpa-et-modèles-recommandés-pour-la-production)  
5. [Valeurs par défaut de la plateforme Aurora](#50-valeurs-par-défaut-de-la-plateforme-aurora)  
6. [Comment VPA fonctionne](#60-comment-vpa-fonctionne)  
7. [Activer VPA sur votre workload](#70-activer-vpa-sur-votre-workload)  
8. [Intégration VPA + HPA](#80-intégration-vpa--hpa)  
9. [Cadres de sécurité pour la production](#90-cadres-de-sécurité-pour-la-production)  
10. [Dépannage](#100-dépannage)  
11. [Plan de mise en œuvre](#110-plan-de-mise-en-œuvre)  
12. [Conclusion](#120-conclusion)  

---

## Contenu détaillé

Les détails techniques complets pour chaque outil, les exemples de code, les modèles de configuration et les directives de production se trouvent dans les diapositives de la présentation :

- **Diapositives en anglais :** `content/slides-en.md`
- **Diapositives en français :** `content/slides-fr.md`

Construisez et consultez-les localement avec `make preview-en` ou `make preview-fr`, ou consultez le site GitHub Pages en direct.

### Référence rapide

| Axe | Outil | Scale | Niveau | Quand |
|-----|-------|--------|--------|-------|
| Taille du pod | VPA | Demandes de ressources | Pod | Historique d'utilisation ; dimensionnement |
| Nombre de réplicas | HPA | Nombre (métrique fixe) | Pod | Métriques CPU/mémoire |
| Nombre de réplicas | KEDA | Nombre (0→N événementiel) | Pod | Événements, files, horaires |
| Infrastructure | Karpenter | Nombre de nœuds | Cluster | Pods en attente |

### Matrice de conflit

|  | HPA | KEDA | VPA | Karpenter |
|---|---|---|---|---|
| **HPA** | OK (même ressource) | CONFLIT (tous deux mettent à l'échelle les réplicas) | OK (ressources divisées) | Complémentaire |
| **KEDA** | CONFLIT (tous deux mettent à l'échelle les réplicas) | OK (scaleurs différents) | OK (ressources divisées) | Complémentaire |
| **VPA** | OK (ressources divisées) | OK (ressources divisées) | CONFLIT (même pod) | Complémentaire |
| **Karpenter** | Complémentaire | Complémentaire | Complémentaire | N/A |

---

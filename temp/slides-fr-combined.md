---
marp: true
theme: default
paginate: true
backgroundColor: "#ffffff"
header: "VPA Usage Guide - Statistics Canada"
footer: "© Statistics Canada - 2026"
size: "16:9"
style: |
  section { font-size: 28px; }
  h1 { font-size: 40px; }
  h2 { font-size: 34px; }
  h3 { font-size: 28px; }
  h4 { font-size: 24px; }
  blockquote { font-size: 26px; }
  table { font-size: 24px; }
---

![bg left:30% height:80px](../img/aurora.png)

<br>

# Vertical Pod Autoscaler (VPA)
## Usage Guide for Aurora Platform

<br>

#### Statistics Canada 2026

*Presented by the SSC Cloud Team*

---
<!-- Title Slide -->
<!-- _class: lead -->
# Vertical Pod Autoscaler (VPA)
![bg right:30% height:200px](./img/aurora.png)

<br>

### Guide d'utilisation pour la plateforme Aurora

<br>
<br>

#### Statistique Canada 2026

*Présenté par l'équipe SSC Cloud*

---

<!-- Executive Summary -->
## Résumé exécutif

![bg left:20%](./img/aurora.png)

- **Quoi:** VPA ajuste automatiquement les demandes de ressources CPU et mémoire pour vos conteneurs selon les modèles d'utilisation réels
- **Pourquoi:** Dimensionner correctement les ressources pour réduire le gaspillage et améliorer l'efficacité du cluster tout en laissant HPA gérer le dimensionnement des réplicas
- **Risque:** Faible - VPA est un outil open-source natif Kubernetes avec une stabilité éprouvée; la plateforme Aurora doit simplement l'adopter
- **Coût:** Minimal - s'exécute en tant que composants système, moins de 1% de surcharge sur le plan de contrôle

<blockquote>
Dimensionnez correctement vos ressources, pas seulement vos réplicas.
</blockquote>

---

<!-- What is VPA? -->
## Qu'est-ce que VPA?

**Vertical Pod Autoscaler (VPA):** Ajuste automatiquement les demandes de ressources CPU et mémoire pour vos conteneurs

![bg left:20%](./img/aurora.png)

- Contrairement à HPA qui dimensionne les *réplicas*, VPA dimensionne les *demandes de ressources*
- Fonctionne avec les Deployments, StatefulSets et DaemonSets
- Deux phases: Recommandeur (analyse) + Updateur (applique)
- Native Kubernetes via les Custom Resource Definitions

<blockquote>
HPA répond "combien de pods?" VPA répond "combien de ressources par pod?"
</blockquote>

**En savoir plus:** <a href="https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/README.md">VPA GitHub</a>

---

<!-- VPA vs HPA -->
## VPA vs HPA: Deux côtés du dimensionnement

| Composant | Ce qu'il scale | Comment ça marche | Quand utiliser |
|-----------|---------------|-------------------|----------------|
| **HPA** | Nombre de réplicas | Scale les pods up/down selon les métriques | Utilisation CPU/mémoire, métriques personnalisées, mise à l'échelle hors heures de pointe |
| **VPA** | Demandes de ressources par conteneur | Ajuste les demandes CPU/mémoire selon l'utilisation | Dimensionnement correct des ressources de conteneur, réduction de la sur-provisionnement |

![bg right:30% height:200px](https://kubernetes.io/images/docs/hpa-vpa.png)

<blockquote>
HPA répond "combien de pods?" VPA répond "combien de ressources par pod?"
</blockquote>

---

<!-- Why VPA Matters -->
## Pourquoi VPA est important

![bg left:20%](./img/aurora.png)

### Le problème des demandes de ressources:
- Sur-provisionnement: 500m CPU quand 100m suffisent → capacité gaspillée
- Sous-provisionnement: 100m CPU quand 500m sont nécessaires → limitation
- Demandes statiques: Ne jamais ajuster après le déploiement

### VPA résout cela:
- **Surveillance continue:** Analyse les modèles d'utilisation au fil du temps
- **Ajustement automatique:** Met à jour les demandes de ressources au fil du temps
- **Dimensionnement correct:** Optimise l'utilisation des ressources du cluster

<blockquote>
Cesser de deviner, commencer à dimensionner avec des données.
</blockquote>

---

<!-- VPA Modes -->
## Modes VPA: Choisissez votre profil de risque

![bg left:20%](./img/aurora.png)

| Mode | Met à jour les pods existants | Éjecte les pods | Utilisation en production |
|------|------------------------------|-----------------|---------------------------|
| **Off** | Non | Non | Analyse seulement |
| **Initial** | Non | Non | Recommandé pour prod |
| **InPlace** | Oui (en place) | Non | Recommandé pour prod |
| **InPlaceOrRecreate** | Oui (fallback) | Oui | Approche équilibrée |
| **Recreate** | Oui | Oui | À utiliser rarement |
| **Auto** | Déconseillé | Déconseillé | Ne pas utiliser |

**Distinction clé:** "Initial" ne met à jour que les nouveaux pods, "InPlace" met à jour les pods existants sans les éjecter.

---

<!-- Recommended VPA Modes -->
## Modes VPA recommandés pour la production

![bg left:20%](./img/aurora.png)

### Pour les workloads en production:
1. **Initial** - Sécurisé, s'applique uniquement à la création du pod
2. **InPlace** - Sans perturbation, met à jour en place quand possible

```yaml
# Mode Initial - appliquer uniquement à la création du pod
updatePolicy:
  updateMode: "Initial"
```

```yaml
# Mode InPlace - essayer la mise à jour en place, ne pas éjecter
updatePolicy:
  updateMode: "InPlace"
```

### Pour le développement/les tests:
- **InPlaceOrRecreate** - Équilibré, essaie d'abord en place
- **Recreate** - Plus agressif, éjecte et recrée

---

<!-- Platform Defaults -->
## Valeurs par défaut de la plateforme Aurora

![bg left:20%](./img/aurora.png)

| Paramètre | Valeur | Description |
|-----------|--------|-------------|
| Version VPA | 0.13.0 (appVersion 1.8.0) | Chart Vertical Pod Autoscaler |
| Espace de noms | vpa-system | Déploiement des composants VPA |
| Metrics Server | Activé | Requis pour que VPA collecte les métriques d'utilisation |
| Contrôleur d'admission | Activé | Webhook modifiant pour la création de pod |
| Prometheus/ServiceMonitor | Désactivé | Peut être activé par workload |

**Déploiement:** Via le chart aurora-core dans l'espace de noms `vpa-system`

---

<!-- How VPA Works -->
## Comment VPA fonctionne: Trois composants

![bg left:20%](./img/aurora.png)

### 1. Recommandeur
- Analyse les modèles d'utilisation des ressources au fil du temps
- Calcule les demandes de ressources recommandées
- S'exécute en continu, met à jour les recommandations

### 2. Updateur
- Vérifie les recommandations VPA par rapport aux spécifications de pod actuelles
- Décide s'il faut mettre à jour les pods et quand
- Respecte les PDB, le statut du rollout et le nombre de réplicas

### 3. Contrôleur d'admission (Webhook modificateur)
- Intercepte les requêtes de création/mise à jour de pod
- Applique les recommandations VPA au moment de l'admission du pod
- Garantit que les nouveaux pods reçoivent des ressources adaptées

---

<!-- VPA Lifecycle -->
## Cycle de vie VPA: Recommandation à application

![bg left:20%](./img/aurora.png)

1. **Le workload s'exécute** → Le serveur de métriques collecte l'utilisation
2. **Le recommandeur analyse** → Calcule les recommandations
3. **Le CRD VPA est mis à jour** → Les recommandations sont stockées
4. **Les nouveaux pods sont créés** → Le contrôleur d'admission les applique
5. **L'updateur évalue** → Décide quand mettre à jour les pods existants

```yaml
# Vérifier les recommandations
kubectl describe vpa my-app-vpa

# Chercher: recommendedContainerResources
```

---

<!-- Enabling VPA -->
## Activer VPA sur votre workload

![bg left:20%](./img/aurora.png)

### Étape 1: Niveau plateforme (déjà fait)
```yaml
# Dans config/config.yaml (aurora-core)
components:
  vpa:
    enabled: true
    metricsServer:
      enabled: true  # Requis
```

### Étape 2: Niveau workload (à votre tour)
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
    updateMode: "Initial"  # Ou "InPlace"
```

---

<!-- Full VPA Example -->
## Exemple complet de ressource VPA

![bg left:20%](./img/aurora.png)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app-vpa
  namespace: my-namespace
  labels:
    team: votre-nom-d'equipe
    environment: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: "Initial"  # Recommandé pour la production
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
## VPA + HPA: Modèle recommandé

![bg left:20%](./img/aurora.png)

### La division des responsabilités:
- **HPA** → Sacle les réplicas (combien de pods)
- **VPA** → Sacle les ressources (combien par pod)

### Critique: Utiliser `controlledResources`

```yaml
# HPA gère le scaling CPU (réplicas)
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

# VPA gère SEULEMENT la mémoire (éviter le conflit)
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
spec:
  resourcePolicy:
    containerPolicies:
      - containerName: "*"
        controlledResources: ["memory"]  # VPA ne gère que la mémoire
```

---

<!-- Production Guardrails -->
## Cadres de sécurité pour la production

![bg left:20%](./img/aurora.png)

### NE PAS:

1. **Utiliser le mode Auto** - Déconseillé et supprimé dans les versions futures
2. **Combiner VPA avec HPA sur les mêmes ressources** - Conflit inévitable
3. **Activer VPA pour les batch jobs** - Utiliser KEDA Jobs à la place
4. **Définir minReplicaCount < 2 avec Recreate** - L'updateur par défaut est 2

### FAIRE:

1. **Utiliser les modes Initial ou InPlace** - Minimiser la perturbation
2. **Définir controlledResources** - Éviter les conflits HPA/VPA
3. **Surveiller les recommandations** - Vérifier l'état VPA hebdomadairement
4. **Utiliser les limites de politiques de ressources** - Définir les bornes min/max

---

<!-- Common Problems -->
## Dépannage: Problèmes courants

![bg left:20%](./img/aurora.png)

### Problème: VPA ne génère pas de recommandations
```bash
# Vérifier Metrics Server
kubectl top nodes
kubectl top pods -n my-namespace

# Vérifier les journaux du recommandeur VPA
kubectl logs -n vpa-system deployment/vpa-recommender
```

### Problème: Recommandations non appliquées
```bash
# Vérifier que les composants VPA sont en cours d'exécution
kubectl get pods -n vpa-system

# Vérifier le contrôleur d'admission
kubectl logs -n vpa-system deployment/vpa-admission-controller
```

### Problème: Pods being éjectés
```bash
# Vérifier le mode VPA
kubectl get vpa my-app-vpa -o yaml

# Envisager de passer au mode InPlace ou Initial
```

---

<!-- Validation Checklist -->
## Liste de vérification de validation

![bg left:20%](./img/aurora.png)

### 1. Vérifier les composants VPA
```bash
kubectl get pods -n vpa-system
# Devrait afficher: recommender, updater, admission-controller tous Running
```

### 2. Vérifier Metrics Server
```bash
kubectl top nodes
# Devrait afficher l'utilisation CPU/mémoire des nœuds
```

### 3. Vérifier les recommandations VPA
```bash
kubectl describe vpa my-app-vpa
# Chercher: recommendedContainerResources
```

### 4. Tester la création de pod
```bash
# Créer un deployment avec VPA
kubectl create deployment test-vpa --image=nginx

# Ajouter VPA, créer un nouveau pod
kubectl rollout restart deployment/test-vpa

# Vérifier que les demandes de ressources ont été appliquées
kubectl describe pod -l app=test-vpa
```

---

<!-- Implementation Plan -->
## Plan de mise en œuvre

![bg left:20%](./img/aurora.png)

### Phase 1: Validation en DEV (semaines 1-2)
- Déployer VPA dans Zone DEV
- Appliquer les politiques de base aux workloads de test
- Surveiller les recommandations et la surcharge
- Documenter les résultats

### Phase 2: Préparation à la production (semaines 3-4)
- Définir les SLO pour la précision des recommandations
- Créer la documentation et les livres de procédures
- Créer le module Terraform pour aurora-platform-charts
- Intégrer avec le provisionnement de cluster

### Phase 3: Automatisation et transmission (semaines 5-6)
- Pipeline CI/CD pour les mises à jour des politiques VPA
- Alertes sur les problèmes VPA
- Formation et documentation
- Rollout organisationnel

---

<!-- Next Steps -->
## Prochaines étapes et questions ouvertes

![bg left:20%](./img/aurora.png)

### Actions immédiates:
1. **Examiner et approuver** cette présentation et cette documentation
2. **Déployer VPA dans DEV** pour tester avec vos workloads
3. **Partager les commentaires** sur les pratiques recommandées

### Questions à investiguer:
- Quelle est la précision typique des recommandations au fil du temps?
- Comment les recommandations changent-elles avec les modèles de workload?
- Quelle est la fréquence optimale de mise à jour VPA?

---

<!-- Conclusion -->
## Conclusion

![bg left:20%](./img/aurora.png)

- **Quoi:** VPA est un outil natif Kubernetes pour le dimensionnement correct des ressources de conteneur
- **Pourquoi:** Réduit le gaspillage, améliore l'efficacité du cluster, complète HPA
- **Comment:** Recommandeur analyse → Updateur applique → Contrôleur d'admission applique
- **Prochaine étape:** Déployer dans DEV, valider avec vos workloads, partager les résultats

<blockquote>
Dimensionnez correctement vos ressources, optimisez votre cluster, réduisez les coûts.
</blockquote>

---

<!-- References -->
## Références

![bg left:20%](./img/aurora.png)

### Documentation VPA:
1. <a href="https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/README.md">Dépôt GitHub VPA</a>
2. <a href="https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/">Dimensionnement horizontal des pods Kubernetes</a>
3. <a href="https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/">Gestion des ressources Kubernetes</a>

### Plateforme Aurora:
4. <a href="https://github.com/gccloudone-aurora/aurora-platform-charts">Charts de la plateforme Aurora</a>
5. Problème d'implémentation VPA #473
6. Épopée de documentation VPA #488

---

<!-- Appendix -->
## Appendix: Détail des modes VPA

![bg left:20%](./img/aurora.png)

### Comparaison des modes de mise à jour:

| Mode | Mise à jour | Éjection | Perturbation du pod | Cas d'utilisation |
|------|-------------|----------|---------------------|-------------------|
| Off | Non | Non | Aucune | Analyse seulement |
| Initial | Non | Non | Aucune | Sécurisé pour la prod |
| InPlace | Oui | Non | Minimale | Sécurisé pour la prod |
| InPlaceOrRecreate | Oui | Oui (fallback) | Quelque peu | Dev/testing |
| Recreate | Oui | Oui | Élevée | Dernier recours |
| Auto | Déconseillé | Déconseillé | N/A | Ne pas utiliser |

### Quand utiliser chaque mode:

- **Initial:** Production, workloads avec redémarrages fréquents
- **InPlace:** Production, quand la perturbation doit être évitée
- **InPlaceOrRecreate:** Dev/testing, quand vous avez besoin de mises à jour rapidement
- **Recreate:** Urgence, quand les autres modes échouent

---
marp: true
theme: default
paginate: true
backgroundColor: "#ffffff"
header: "Mise à l'échelle sur Kubernetes - Plateforme Aurora"
footer: "© Aurora - 2026"
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

# Mise à l'échelle sur Kubernetes
## VPA, KEDA et Karpenter sur la plateforme Aurora

<br>

#### Aurora Platform Team 2026

*Mise à l'échelle des workloads et des nœuds : guide pour l'équipe plateforme*

---

<!-- Overview -->
## Ce que couvre ce guide

![bg left:20%](./img/aurora.png)

Trois autoscalers qu'Aurora exploite, et comment ils s'articulent :

- **VPA** - dimensionne les demandes CPU/mémoire des pods
- **KEDA** - mise à l'échelle des réplicas pilotée par événements et horaires (jusqu'à zéro)
- **Karpenter** - provisionnement de nœuds juste-à-temps et consolidation

<blockquote>
Des outils différents, des axes différents. La valeur est dans leur combinaison.
</blockquote>

---

<!-- Scaling axes map -->
## La carte de mise à l'échelle : trois axes, quatre outils

![bg left:20%](./img/aurora.png)

| Axe | Outil(s) | Échelle | Niveau | Déclencheur |
|-----|---------|---------|--------|-------------|
| **Nombre de réplicas** | HPA, KEDA | Réplicas | Pod | Métriques (HPA) ou événements/horaires (KEDA) |
| **Taille des ressources** | VPA | Demandes+limites CPU/mémoire | Pod | Historique d'utilisation |
| **Capacité des nœuds** | Karpenter | Nœuds | Infrastructure | Pods en attente |

<blockquote>
Nombre de réplicas x taille par pod = la demande de pods que Karpenter satisfait.
</blockquote>

---

<!-- How they layer -->
## Comment ils s'empilent

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">HPA / KEDA</div>
    <div class="plate">Décident du nombre</div>
    <div class="plate">de réplicas</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">VPA</div>
    <div class="plate">Fixe les demandes</div>
    <div class="plate">CPU / mémoire</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Karpenter</div>
    <div class="plate">Provisionne les nœuds</div>
    <div class="plate">adaptés aux pods</div>
  </div>
</div>

<blockquote>
Nombre de réplicas x taille par pod = la demande de pods que Karpenter satisfait.
</blockquote>

---

<!-- ============================ PARTIE 1: VPA ============================ -->
<!-- VPA section divider -->
# Partie 1 : VPA
## Dimensionnement des ressources des pods

![bg left:30%](./img/aurora.png)

---

<!-- What is VPA? -->
## Qu'est-ce que VPA ?

**Vertical Pod Autoscaler :** ajuste automatiquement les demandes CPU et mémoire *et les limites* de vos conteneurs

![bg left:20%](./img/aurora.png)

- Contrairement à HPA qui dimensionne les *réplicas*, VPA dimensionne les *demandes/limites de ressources*
- Fonctionne avec Deployments, StatefulSets, DaemonSets
- Composé de trois composants : Recommandeur, Updateur et Contrôleur d'admission
- Natif Kubernetes via les Custom Resource Definitions
- Par défaut, dimensionne les demandes et limites proportionnellement ; utilisez `controlledValues: RequestsOnly` pour les demandes uniquement

<blockquote>
HPA dimensionne combien, VPA dimensionne quelle taille.
</blockquote>

---

<!-- Why VPA Matters -->
## Pourquoi VPA est important

![bg left:20%](./img/aurora.png)

### Le problème des demandes de ressources :
- Sur-provisionnement : 500m CPU quand 100m suffisent, capacité gaspillée
- Sous-provisionnement : 100m CPU quand 500m nécessaires, throttling
- Les demandes statiques ne s'ajustent jamais après le déploiement

### VPA résout cela :
- **Dimensionnement à la création de pods :** le mode Initial applique les recommandations uniquement aux nouveaux pods
- **Surveillance continue :** le Recommandeur analyse l'utilisation au fil du temps
- **Mises à jour contrôlées :** l'Updateur peut progressivement déployer des changements via les mises à jour InPlace (si disponibles)

<blockquote>
Cessez de deviner, dimensionnez avec des données.
</blockquote>

---

<!-- How VPA Works -->
## Comment VPA fonctionne : trois composants

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">Recommandeur</div>
    <div class="plate">Analyse les modèles d'utilisation</div>
    <div class="plate">Calcule les recommandations</div>
    <div class="plate">S'exécute en continu</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Updateur</div>
    <div class="plate">Vérifie les recommandations</div>
    <div class="plate">Décide quand mettre à jour</div>
    <div class="plate">Respecte PDB/rollout</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Contrôleur d'admission</div>
    <div class="plate">Intercepte les requêtes</div>
    <div class="plate">Applique les recommandations</div>
    <div class="plate">Garantit des ressources adaptées</div>
  </div>
</div>

---

<!-- VPA Modes -->
## Modes VPA : choisissez votre profil de risque

![bg left:20%](./img/aurora.png)

| Mode | Met à jour pods existants | Éjecte | Usage en production |
|------|---------------------------|--------|---------------------|
| **Off** | Non | Non | Analyse seulement |
| **Initial** | Non | Non | Recommandé pour prod |
| **InPlace** | Oui (en place) | Non | Recommandé pour prod |
| **InPlaceOrRecreate** | Oui (fallback) | Oui | Équilibré, dev/test |
| **Recreate** | Oui | Oui | À utiliser rarement |
| **Auto** | Déconseillé | Déconseillé | Ne pas utiliser |

**Distinction clé :** « Initial » ne met à jour que les nouveaux pods ; « InPlace » met à jour les pods existants sans éviction.

> `InPlace` nécessite le feature gate `InPlacePodVerticalScaling` et une version VPA récente, sinon il recrée le pod.

---

<!-- Aurora VPA defaults -->
## VPA sur Aurora : valeurs par défaut

![bg left:20%](./img/aurora.png)

| Paramètre | Valeur |
|-----------|--------|
| Version VPA | 1.7 (dernière ; appVersion 1.35+) |
| Espace de noms | vpa-system |
| Metrics Server | Activé (requis) |
| Contrôleur d'admission | Activé (webhook mutateur) |
| Prometheus/ServiceMonitor | Désactivé (opt-in par workload) |

**Déploiement :** via le chart aurora-core. L'activation au niveau plateforme est déjà faite.

---

<!-- VPA example -->
## Exemple VPA

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
    updateMode: "Initial"   # ou "InPlace"
  resourcePolicy:
    containerPolicies:
      - containerName: "*"
        minAllowed: { cpu: 50m, memory: 64Mi }
        maxAllowed: { cpu: 500m, memory: 512Mi }
        controlledValues: "RequestsAndLimits"  # ou "RequestsOnly"
        controlledResources: ["cpu", "memory"]
```

**Les bornes comptent :** `minAllowed` prévient la sous-estimation (garde les pods ordonnançables) ; `maxAllowed` prévient la sur-estimation. Dimensionne les demandes et limites proportionnellement par défaut.

---

<!-- VPA limitations -->
## VPA : quand NE PAS l'utiliser

![bg left:20%](./img/aurora.png)

- **Charges en pics :** VPA réagit à l'historique ; les pics soudains peuvent être sous-provisionnés
- **Applications JVM / réglées sur le tas :** changer la mémoire ne change pas `-Xmx` ; dimensionnez le runtime
- **Charges sensibles aux évictions :** évitez `Recreate` quand les redémarrages coûtent cher
- **Même ressource que HPA/KEDA :** ne laissez jamais deux contrôleurs se disputer la même ressource (voir Partie 4)
- **Processus très éphémères :** VPA a besoin de temps pour collecter et analyser les données d'utilisation

---

<!-- ============================ PARTIE 2: KEDA ============================ -->
<!-- KEDA section divider -->
# Partie 2 : KEDA
## Mise à l'échelle par événements et horaires

![bg left:30%](./img/aurora.png)

---

<!-- What is KEDA -->
## Qu'est-ce que KEDA ?

**Kubernetes Event-Driven Autoscaler :** dimensionne les réplicas selon des événements, files ou horaires

![bg left:20%](./img/aurora.png)

- Réagit à des signaux externes : lag Kafka, profondeur de file, cron, métriques personnalisées
- Peut **descendre à zéro** quand il n'y a rien à faire
- Pilote un HPA standard en interne (vous ne créez pas le HPA vous-même)
- Config via `ScaledObject` (longue durée) ou `ScaledJob` (batch)

<blockquote>
HPA réagit au CPU. KEDA réagit à ce qui pilote réellement votre charge.
</blockquote>

---

<!-- KEDA Aurora defaults -->
## KEDA sur Aurora : valeurs par défaut

![bg left:20%](./img/aurora.png)

| Paramètre | Valeur |
|-----------|--------|
| Version KEDA | 2.16+ (dernière stable) |
| Espace de noms | keda-system |
| Metrics Server | Activé (requis) |
| Prometheus/ServiceMonitor | Désactivé (opt-in par workload) |

**Deux façons de l'utiliser :**
- **Mise à l'échelle hors heures native** (recommandé) : `offHoursScaling` dans le chart aurora-namespace ; les ScaledObjects sont générés
- **ScaledObject manuel :** pour événements, files, ou logique personnalisée

---

<!-- KEDA platform-native -->
## KEDA : mise à l'échelle hors heures native

![bg left:20%](./img/aurora.png)

Recommandé pour la mise à l'échelle selon les heures d'affaires. Désactivé par défaut.

```yaml
offHoursScaling:
  enabled: true
  defaultSchedule:
    start: "0 7 * * 1-5"        # lun-ven 7:00
    end: "0 19 * * 1-5"         # lun-ven 19:00
    timezone: "America/Toronto"
  minReplicas: 1                # garder 1 hors heures (prod)
  workloads:
    - name: my-api
      businessHoursReplicas: 2
```

Le chart génère pour vous les ScaledObjects, labels et annotations conformes.

---

<!-- KEDA manual -->
## KEDA : ScaledObject manuel

![bg left:20%](./img/aurora.png)

Pour événements, files, ou descente à zéro (hors prod).

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
spec:
  scaleTargetRef:
    name: my-app-deployment
  minReplicaCount: 0            # descente à zéro (hors prod)
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
## KEDA : garde-fous en production

![bg left:20%](./img/aurora.png)

### NE PAS :
- **Utiliser KEDA et votre propre HPA ensemble** - KEDA crée et gère le HPA ; vous ne gérez que le ScaledObject
- **Créer votre propre HPA** pour un workload géré par KEDA - KEDA le possède
- **Vous fier à des cooldowns courts pour l'isolement** - `cooldownPeriod` (par défaut 300s) n'affecte que le passage final de zéro, pas la réduction générale (c'est la fenêtre `behavior` de HPA)

### FAIRE :
- Gardez `minReplicaCount: 1`+ en production (pas de descente à zéro)
- Ajoutez `terminationGracePeriodSeconds` pour les consommateurs longue durée
- Utilisez `ScaledJob` pour le traitement batch événementiel
- Validez sur un cycle complet de 24 heures en hors prod

---

<!-- ============================ PARTIE 3: Karpenter ============================ -->
<!-- Karpenter section divider -->
# Partie 3 : Karpenter
## Provisionnement de nœuds juste-à-temps

![bg left:30%](./img/aurora.png)

---

<!-- What is Karpenter -->
## Qu'est-ce que Karpenter ?

**Autoscaler de nœuds agnostique :** provisionne des nœuds juste-à-temps pour les pods en attente, puis consolide

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">Surveiller</div>
    <div class="plate">Pod que l'ordonnanceur</div>
    <div class="plate">ne peut pas placer</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Provisionner</div>
    <div class="plate">Le nœud le moins cher</div>
    <div class="plate">qui convient au pod</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Consolider</div>
    <div class="plate">Repack des workloads</div>
    <div class="plate">Retrait des nœuds inactifs</div>
  </div>
</div>

<blockquote>
Le Cluster Autoscaler dimensionne des pools prédéfinis. Karpenter choisit le bon nœud selon la demande, puis range.
</blockquote>

---

<!-- Karpenter why -->
## Pourquoi Karpenter plutôt que Cluster Autoscaler

![bg left:20%](./img/aurora.png)

| Aspect | Cluster Autoscaler | Karpenter |
|--------|-------------------|-----------|
| Provisionnement de nœuds | Ajoute des nœuds un par un à un groupe | Provisionne un seul nœud adapté à chaque pod en attente |
| Sélection d'instance | Utilise des expanders (least-waste, price, priority) | Choisit le type le moins cher qui convient |
| Consolidation | Supprime les nœuds sous-utilisés après drainage | Repack et suppression de nœuds continus |
| Multi-famille | Pool statique par groupe | N'importe quelle famille, spot + on-demand mélangés |
| Vitesse de provisionnement | Minutes | ~45-60s (benchmark fournisseur) |

> Réduction de coûts estimée de 20-40 % vs Cluster Autoscaler ([étude de cas AWS](https://repost.aws/articles/AR5C03QTEyRgKoDI-XO5UC7w/optimizing-your-amazon-eks-compute-costs-with-karpenter)) - à valider en pilote.

---

<!-- Karpenter NodePool -->
## Karpenter : NodePool comme source de vérité

![bg left:20%](./img/aurora.png)

Définissez l'intention une fois ; adaptez le `nodeClassRef` spécifique au fournisseur par plateforme (EC2NodeClass, AKSNodeClass, GKENodeClass, etc).

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        name: default           # pointe vers EC2NodeClass, AKSNodeClass, etc (spécifique au fournisseur)
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]   # préférer spot
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30m    # ajuster à la tolérance au churn
  limits:
    cpu: "1000"              # prévenir le provisionnement incontrôlé
```

---

<!-- Karpenter Aurora -->
## Karpenter sur Aurora : la stratégie

![bg left:20%](./img/aurora.png)

**Objectif :** Construire une expertise Karpenter interne pour l'utiliser entre clouds, en se rabattant sur les solutions gérées des CSP quand elles suffisent.

- **AWS :** Karpenter auto-hébergé (fournisseur v1 GA, contrôle total)
- **Azure :** Essayer AKS NAP (Karpenter géré) ; basculer à l'auto-hébergé si des contraintes apparaissent
- **GKE :** Karpenter auto-hébergé (via [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp))
- **On-premises :** Karpenter auto-hébergé (vous possédez l'infrastructure)

**Pourquoi l'auto-hébergé quand possible :**
- Mêmes APIs NodePool sur toutes les plateformes
- Contrôle complet des versions et balayage de sécurité
- Évite la manipulation des coûts par le CSP
- Liberté de migration si une solution CSP ne répond pas aux objectifs

**Compromis Azure NAP :** Simplicité gérée maintenant, mais risque de verrouillage du fournisseur plus tard.

<blockquote>
Apprenez Karpenter. Utilisez NAP du CSP s'il fonctionne. Revenez à l'auto-hébergé si des contraintes émergeaient.
</blockquote>

---

<!-- Karpenter limitations -->
## Karpenter : risques et mises en garde

![bg left:20%](./img/aurora.png)

- **Le fournisseur GCP est maintenu par la communauté :** le [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp) est pré-1.0 ; des changements cassants surviennent. Épinglez les versions, scannez, gardez l'Autoscaling GKE comme fallback
- **Churn de nœuds :** une consolidation agressive perturbe les pods ; ajustez `consolidateAfter` et utilisez des PodDisruptionBudgets
- **Compromis Azure NAP :** plus simple maintenant, mais difficile de basculer plus tard si des contraintes apparaissent (APIs spécifiques du fournisseur, verrouillage des versions, contrôle des coûts)
- **Changement de modèle :** le choix de l'autoscaler est défini à la création du cluster sur toutes les plateformes
- **Définissez `limits`** sur NodePool pour prévenir le provisionnement incontrôlé
- **Apprenez Karpenter d'abord :** comprenez le projet open-source avant de choisir une variante gérée

---

<!-- ============================ PARTIE 4: Interactions ============================ -->
<!-- Interactions divider -->
# Partie 4 : L'assemblage
## Interactions et anti-patrons

![bg left:30%](./img/aurora.png)

---

<!-- The combined picture -->
## Comment ça fonctionne : L'image complète

![bg left:20%](./img/aurora.png)

1. **KEDA / HPA** décident du nombre de réplicas (pilotés par événements ou métriques)
2. **VPA** dimensionne chaque pod selon l'historique d'utilisation
3. **Combiné :** Nombre de réplicas × taille par pod = demande totale de pods
4. **Karpenter** surveille les pods non ordonnançables et provisionne les nœuds

<blockquote>
Les trois alimentent un seul pipeline. Gardez-les hors des axes des autres et ils se renforcent.
</blockquote>

---

<!-- Conflict rules -->
## Les règles qui les empêchent de se battre

![bg left:20%](./img/aurora.png)

| Paire | Règle |
|-------|-------|
| **VPA + HPA** | Jamais la même ressource. VPA = mémoire, HPA = CPU (`controlledResources`) |
| **VPA + KEDA** | Conflit uniquement avec déclencheurs CPU/mémoire. Sûr avec profondeur de file, cron, ou métriques personnalisées |
| **KEDA + votre HPA** | Ne créez pas votre propre HPA ; KEDA le possède (`transfer-hpa-ownership` au besoin) |
| **VPA + Karpenter** | Complémentaires : VPA change les demandes, Karpenter repack. Définissez `maxAllowed` et `limits` |
| **KEDA 0 + Karpenter** | Descente à zéro + consolidation vide et retire les nœuds. Attention au cold start |

---

<!-- Anti-patterns -->
## Anti-patrons à éviter

![bg left:20%](./img/aurora.png)

- **VPA et HPA/KEDA sur la même métrique** - ils se disputent la même ressource et oscillent
- **VPA `Recreate` sur des workloads sensibles aux évictions** - préférez Initial/InPlace
- **Descente à zéro en production** sans planifier la latence du cold start
- **Pas de `maxAllowed` sur VPA / pas de `limits` sur NodePool** - une recommandation excessive peut épingler un nœud
- **Consolidation agressive sans PodDisruptionBudgets** - le churn de nœuds perturbe ; utilisez `consolidateAfter` et PDB

---

<!-- Conclusion -->
## Conclusion

![bg left:20%](./img/aurora.png)

- **VPA** dimensionne les pods (quelle taille)
- **KEDA** dimensionne les réplicas selon la demande réelle, jusqu'à zéro (combien)
- **Karpenter** provisionne et consolide les nœuds (quelle capacité)
- **Ensemble** ils forment un pipeline : gardez-les hors des axes des autres et ils se renforcent

<blockquote>
Dimensionnez les pods, échelonnez selon la demande réelle, provisionnez seulement ce qui convient.
</blockquote>

---

<!-- References -->
## Références

![bg left:20%](./img/aurora.png)

### Amont :
1. <a href="https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/README.md">VPA (kubernetes/autoscaler)</a>
2. <a href="https://keda.sh/docs/">Documentation KEDA</a>
3. <a href="https://karpenter.sh/">Documentation Karpenter</a>

### Plateforme Aurora :
4. <a href="https://github.com/gccloudone-aurora/aurora-platform-charts">Aurora Platform Charts</a>
5. Guides d'utilisation VPA / KEDA et la proposition d'autoscaling Karpenter (docs-main)

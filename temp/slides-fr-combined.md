---
marp: true
theme: default
paginate: true
backgroundColor: "#ffffff"
header: "Mise à l'échelle sur Kubernetes - Plateforme Aurora"
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

# Mise à l'échelle sur Kubernetes
## VPA, KEDA et Karpenter sur la plateforme Aurora

<br>

#### Aurora Platform Team 2026

*Mise à l'échelle des workloads et des nœuds : guide pour l'équipe plateforme*

---

<!-- Overview -->
## Ce que couvre ce guide

![bg left:20%](./img/aurora.png)

Mise à l'échelle sur Aurora : comprendre comment les autoscalers s'articulent

- **VPA** - dimensionne les demandes CPU/mémoire des pods
- **KEDA** - mise à l'échelle des réplicas pilotée par événements et horaires (jusqu'à zéro)
- **Karpenter** - provisionnement de nœuds juste-à-temps et consolidation

<br>

<blockquote>
Des outils différents, des axes différents. La valeur est dans leur combinaison.
</blockquote>

---

<!-- Scaling axes map -->
## La carte de mise à l'échelle : trois axes

<div class="flow">
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">KEDA</div>
    <div class="plate">Met à l'échelle les réplicas</div>
    <div class="plate">Piloté par événements & files</div>
    <div class="plate"><i>(Combien de pods)</i></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">VPA</div>
    <div class="plate">Dimensionne les ressources des pods</div>
    <div class="plate">Ajuste les demandes & limites</div>
    <div class="plate"><i>(Quelle taille de pod)</i></div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box" style="width: 32%;">
    <div class="plate plate-head">Karpenter</div>
    <div class="plate">Provisionne les nœuds dimensionnés</div>
    <div class="plate">Lie les pods en attente au calcul</div>
    <div class="plate"><i>(Où les pods s'adaptent)</i></div>
  </div>
</div>

<br>

<blockquote>
Nombre de réplicas × taille par pod = la demande de pods que Karpenter satisfait.
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

**Vertical Pod Autoscaler :** ajuste automatiquement les demandes et limites CPU/mémoire des pods Kubernetes en fonction de l'utilisation en temps réel et des bornes prédéfinies

* **Cibles :** Demandes et limites CPU/mémoire des workloads
* **Workloads :** Deployments, StatefulSets, DaemonSets
* **Architecture :** Recommandeur, Updateur, Contrôleur d'admission
* **Natifs :** Mis en œuvre via les CRDs standards
* **Configuration :** Utilisez `controlledValues: RequestsOnly` pour protéger les limites personnalisées

<br>

<blockquote>
HPA met à l'échelle combien, VPA met à l'échelle quelle taille.
</blockquote>

---

<!-- Why VPA Matters: Initial Mode Focus -->
## VPA en production : Dimensionnement à Day-Zero

La plus grande barrière à l'efficacité des ressources est le **piège de la base statique**—les ingénieurs codent en dur des valeurs génériques de ressources lors du déploiement et ne les modifient jamais.

### Entrée en jeu du mode `Initial` : Le dimensionnement à la naissance du pod
Au lieu de modifier dynamiquement l'infrastructure en cours d'exécution, VPA peut agir comme un **injecteur intelligent de template** au moment exact où un pod naît.

* **Ingestion historique :** Le Recommandeur suit en continu l'empreinte réelle de votre application en production en arrière-plan.
* **Mutation à la naissance :** Lorsqu'un déploiement déclenche un rollout ou qu'un pod redémarre, le Contrôleur d'admission intercepte la requête *avant* son planification.
* **Télémétrie plutôt que devinettes :** VPA supprime les chiffres codés en dur par le développeur et injecte une cible de ressources exacte et pilotée par les données.
* **Zéro churn en production :** Une fois le pod en cours d'exécution, VPA verrouille les paramètres. Il n'**éjectera ni ne redémarrera jamais** un conteneur en vol.

<br>

<blockquote>
Profils plutôt que prédictions. Verrouillez l'empreinte optimale dès le jour zéro, sans risque runtime.
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

<br>

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
    <div class="plate">Respecte les budgets de disruption de pod/rollout</div>
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

<!-- How the Recommender works -->
## Comment le Recommandeur fonctionne

![bg left:25%](./img/aurora.png)

Le "cerveau" fondamental de VPA. Il ne fait que **proposer** des métriques - il ne modifie jamais les pods en cours d'exécution.

1. **Surveillance continue** - Extrait l'utilisation du Metrics Server/Prometheus
2. **Analyse historique** - Moyenne mobile décroissante, les pics comptent le plus (pas d'OOM !)
3. **Génération des cibles** - Calcule et écrit quatre zones cibles dans le statut VPA

---

<!-- In-Place Resizing -->
## Redimensionnement en place : right-sizing sans interruption

![bg left:25%](./img/aurora.png)

Modifie l'allocation CPU et mémoire à la volée sans éviction ni redémarrage des pods en cours d'exécution.

Pour obtenir une mise à l'échelle à interruption nulle, quatre couches doivent s'aligner :
- **Runtime de l'application :** Les runtimes absorbent sans heurts la CPU supplémentaire, mais la mise à l'échelle mémoire exige le suivi dynamique des cgroups (ex: configurer les bornes du tas JVM)
- **Capacité nœud :** Le nœud physique sous-jacent doit avoir immédiatement de la marge (capacité de rechange) pour accueillir une demande de montée en charge
- **Gestion des risques :** Le downscaling exige des garde-fous ; réduire trop agressivement l'allocation mémoire déclenchera instantanément des tués OOM (Out-Of-Memory)
- **Moteur plateforme :** Géré automatiquement par Aurora sur Kubernetes 1.27+ via le feature gate `InPlacePodVerticalScaling`

<br>

<blockquote>
Fallback : <b>InPlaceOrRecreate</b> retourne à l'éviction si l'espace nœud ou la compatibilité runtime est verrouillée.
</blockquote>

---

<!-- VPA Modes -->
## Modes VPA : choisissez votre profil de risque

![bg left:20%](./img/aurora.png)

| Mode | Met à jour pods existants | Éjecte | Usage en production |
|------|---------------------------|--------|---------------------|
| **Off** | Non | Non | Analyse seulement |
| **Initial** | Non | Non | Recommandé pour prod |
| **InPlace** | Oui (en place, sans eviction) | No* | Recommandé pour prod |
| **InPlaceOrRecreate** | Oui (en place d'abord, puis recréation) | Oui (si InPlace échoue) | Équilibré, dev/test |
| **Recreate** | Oui (seulement via eviction) | Oui | À utiliser rarement |
| **Auto** | Déconseillé | Déconseillé | Ne pas utiliser |

* Nécessite le feature gate `InPlacePodVerticalScaling` et une version Kubernetes qui le supporte. Recrée le pod si indisponible.

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
- **Même ressource que KEDA :** ne laissez jamais deux contrôleurs se disputer la même ressource (voir Partie 4)
- **Processus très éphémères :** VPA a besoin de temps pour collecter et analyser les données d'utilisation

> **C'est l'axe 'quelle taille'.** Ensuite : KEDA décide *combien* de réplicas vous avez besoin.

---

<!-- ============================ PARTIE 2: KEDA ============================ -->
<!-- KEDA section divider -->
# Partie 2 : KEDA
## Mise à l'échelle par événements et horaires

![bg left:30%](./img/aurora.png)

---

<!-- What is KEDA -->
## Qu'est-ce que KEDA ?

**Kubernetes Event-Driven Autoscaler :** dimensionne les réplicas selon des événements, files ou horaires cron

![bg left:20%](./img/aurora.png)

- Met à l'échelle sur des signaux externes : lag Kafka, profondeur de file, horaires cron, ou trafic HTTP
- Fonctionne comme un broker : traduit les métriques externes en cibles HPA natives
- Permet la descente à zéro : décharge en toute sécurité les workloads inactifs jusqu'à 0 réplicas
- Config via `ScaledObject` (longue durée) ou `ScaledJob` (batch)

<br>

<blockquote>
HPA réagit au CPU. KEDA réagit à ce qui pilote réellement votre charge.
</blockquote>

---

<!-- Comment KEDA fonctionne -->
## Comment KEDA fonctionne

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">ScaledObject</div>
    <div class="plate">Vous définissez :</div>
    <div class="plate">Événements, déclencheurs, règles</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Opérateur KEDA</div>
    <div class="plate">Crée & gère :</div>
    <div class="plate">HPA standard en coulisses</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">HPA</div>
    <div class="plate">Contrôle le nombre de réplicas</div>
    <div class="plate">de votre déploiement</div>
  </div>
</div>

> **Vous configurez seulement le ScaledObject.** KEDA possède l'HPA et le maintient synchronisé avec vos règles de scaling pilotées par les événements.

---

<!-- Pourquoi KEDA est important -->
## Pourquoi KEDA est important

![bg left:20%](./img/aurora.png)

### Le problème du dimensionnement des réplicas :
- **HPA sur CPU/mémoire :** scale trop tard - quand le CPU est déjà haut, il est déjà trop tard
- **Réplicas statiques :** soit sur-provisionné (capacité gaspillée), soit sous-provisionné (mauvaise UX)
- **Scaling manuel :** réactif, source d'erreurs, épuisant

### KEDA résout cela :
- **Scaling piloté par les événements :** commencez à scale *avant* que le CPU ne monte - lag Kafka, profondeur de file, ou alertes Prometheus
- **Descente à zéro :** quand il n'y a rien à faire, exécutez 0 réplicas. Quand le trafic arrive, scalez vers N
- **Intégration HPA :** KEDA crée et possède l'HPA ; vous configurez seulement le ScaledObject

<br>

<blockquote>
Scalez sur ce qui pilote votre charge, pas sur ce qu'il semble après le fait.
</blockquote>

---

<!-- KEDA Aurora defaults -->
## KEDA sur Aurora

![bg left:20%](./img/aurora.png)

| Paramètre | Valeur |
|-----------|--------|
| Version KEDA | 2.20.2 (dernière stable) |
| Espace de noms | keda-system |
| Metrics Server | Activé (requis) |
| Prometheus/ServiceMonitor | Désactivé (opt-in par workload) |

<br>

<blockquote>
KEDA est le moyen natif de la plateforme pour mettre à l'échelle les réplicas selon les signaux de demande réels.
</blockquote>

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
  minReplicaCount: 0            # descente à zéro (hors prod seulement)
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
- **Utiliser KEDA alongside votre propre HPA** - KEDA crée et gère l'HPA ; vous configurez seulement le ScaledObject
- **Rely on short cooldowns for isolation** - `cooldownPeriod` (par défaut 300s) n'affecte que la descente finale à zéro, pas la réduction générale (c'est la fenêtre `behavior` de HPA)

### FAIRE :
- Gardez `minReplicaCount: 1`+ en production (pas de descente à zéro)
- Ajoutez `terminationGracePeriodSeconds` pour les consommateurs longue durée
- Utilisez `ScaledJob` pour le traitement batch événementiel
- Validez sur un cycle complet de 24 heures en hors prod

> **Astuce :** Pensez à KEDA comme le service HPA - vous configurez ce qui doit être mis à l'échelle (ScaledObject), KEDA gère le contrôleur HPA réel en coulisses.

> **C'est l'axe 'combien'.** Ensuite : Karpenter provisionne *quelle capacité* pour les pods.

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
    <div class="plate">Bin-packing de tous les pods</div>
    <div class="plate">Nœud exact-le moins cher</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Consolider</div>
    <div class="plate">Repack et retire les nœuds</div>
    <div class="plate">Respecte les budgets de disruption de pod</div>
  </div>
</div>

> **Le grand changement :** Karpenter contourne les groupes de nœuds. Il parle directement à l'API du fournisseur avec une intelligence de bin-packing.

---

<!-- Karpenter deep dive -->
## Comment Karpenter fonctionne : trois étapes

![bg left:20%](./img/aurora.png)

| Étape | Ce qui se passe | Pourquoi c'est important |
|-------|----------------|-------------------------|
| **1. Surveiller** | Piloté par les événements : surveille les pods non ordonnançables milliseconde par milliseconde | Pas de délai de polling → ~45s pour monter |
| **2. Provisionner** | Bin-packing de tous les pods sur le nœud exact-le moins cher | 3-4 pods sur un nœud à 15$/mois, pas 3x 100$/mois |
| **3. Consolider** | Repack les workloads, retire les nœuds inactifs (vide, swap nœud unique, multi-nœuds) | Économise 20-40% vs Cluster Autoscaler |

**Capacités clés :**
- **Accès direct à l'API :** Pas de Auto Scaling Groups - crée un nœud parfait par demande
- **Bin-packing :** Agrège tous les pods, trouve le placement optimal
- **Respects les budgets de disruption de pod :** Attendra pour drainer les nœuds tant que les PDB le permettent ; ne terminera jamais de force les pods pendant la consolidation
- **Attributs de nœuds :** Lit nodeSelector, affinités, tolerations, GPUs

<br>

<blockquote>
Le Cluster Autoscaler ajoute aux pools prédéfinis. Karpenter construit le nœud parfait par demande de pod.
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
## Karpenter sur Aurora

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

<br>

<blockquote>
Apprenez Karpenter. Utilisez NAP du CSP s'il fonctionne. Revenez à l'auto-hébergé si des contraintes émergeaient.
</blockquote>

---

<!-- Karpenter limitations -->
## Karpenter : risques et mises en garde

![bg left:20%](./img/aurora.png)

- **Le fournisseur GCP est maintenu par la communauté :** le [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp) est pré-1.0 ; des changements cassants surviennent. Épinglez les versions, scannez, et gardez GKE Workload Autoscaler comme fallback
- **Churn de nœuds :** une consolidation agressive perturbe les pods ; ajustez `consolidateAfter` et utilisez des PodDisruptionBudgets
- **Azure NAP (Karpenter géré) :** plus simple maintenant, mais [github.com/Azure/karpenter-provider-azure/issues/1351](https://github.com/Azure/karpenter-provider-azure/issues/1351) indique des limites actuelles ; envisagez l'auto-hébergé pour un contrôle complet
- **Changement de modèle :** le choix de l'autoscaler est défini à la création du cluster sur toutes les plateformes
- **Définissez `limits`** sur NodePool pour prévenir le provisionnement incontrôlé
- **Apprenez Karpenter d'abord :** comprenez le projet open-source avant de choisir une variante gérée

> **C'est l'axe infrastructure.** Vous avez maintenant : VPA (quelle taille) + KEDA (combien) + Karpenter (quelle capacité) = un pipeline complet.

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

1. **KEDA** décide du nombre de réplicas (événements, files, horaires)
2. **VPA** dimensionne chaque pod selon l'historique d'utilisation
3. **Combiné :** Nombre de réplicas × taille par pod = demande totale de pods
4. **Karpenter** surveille les pods non ordonnançables et provisionne les nœuds

<br>

<blockquote>
Les trois alimentent un seul pipeline. Gardez leurs axes découplés pour une mise à l'échelle optimale et correctement dimensionnée.
</blockquote>

---

<!-- Conflict rules -->
## Les règles qui les empêchent de se battre

![bg left:20%](./img/aurora.png)

| Paire | Règle |
|-------|-------|
| **VPA + HPA** | Jamais la même ressource. VPA = mémoire, HPA = CPU (`controlledResources`) |
| **VPA + KEDA** | Conflit uniquement avec déclencheurs CPU/mémoire. Sûr avec profondeur de file, cron, ou métriques personnalisées |
| **KEDA + HPA** | Ne configurez pas à la fois le ScaledObject de KEDA et votre propre HPA pour le même déploiement — KEDA crée et possède l'HPA sous-jacent automatiquement |
| **VPA + Karpenter** | Complémentaires : VPA change les demandes, Karpenter repack. Définissez `maxAllowed` et `limits` |
| **KEDA 0 + Karpenter** | Descente à zéro + consolidation vide et retire les nœuds. Attention au cold start |

<!-- What could go wrong -->
## Qu'est-ce qui pourrait mal tourner

![bg left:20%](./img/aurora.png)

**La mise à l'échelle automatique est comme un moteur de jet haute performance.** Si les systèmes de contrôle sont décalés, les ailes commencent à vibrer violemment—ce qu'on appelle le *flapping*—jusqu'à ce que la friction déchire votre disponibilité.

| Mode d'échec | Ce qui se passe | Le coût |
|--------------|----------------|---------|
| **Spirale mortelle** | HPA et VPA se battent sur CPU. Pods montent, shring, CPU remonte, montent encore. | Surcharge API server. Latence utilisateurs. |
| **Whiplash Karpenter** | Burst file → 100 pods → nœud $1000. Burst finit → 1 pod → nœud détruit. Répétition. | Coût cloud massif. Instabilité nœuds. |
| **Cascade OOM** | Fuite mémoire → VPA augmente mémoire → fuite consomme plus → nœud OOM → kernel tue tous pods. | Single app prend tout le monde sur le nœud. |
| **Capacité fantôme** | KEDA monte à 200, Karpenter commande nœuds Spot. Spot indisponible → KEDA passe à 400. | 500 pods bootés pour une demande de 200. |

> **Souvenez-vous :** Gardez les métriques découplées. VPA (mémoire), KEDA (CPU/traffic), Karpenter (pods en attente).

---

<!-- Conclusion -->
## Conclusion

![bg left:20%](./img/aurora.png)

- **VPA** dimensionne les pods (quelle taille)
- **KEDA** met à l'échelle les réplicas selon la demande réelle, jusqu'à zéro (combien)
- **Karpenter** provisionne et consolide les nœuds (quelle capacité)
- **Ensemble, ils forment un moteur de mise à l'échelle unique :** gardez leurs métriques découplées et leur efficacité se multiplie.

<br>

<blockquote>
Dimensionnez les pods, mettez à l'échelle sur la demande réelle, provisionnez seulement ce qui convient.
</blockquote>

---

<!-- Afterword: FAQs -->
## Appendix: FAQs

![bg left:20%](./img/aurora.png)

---

### Groupe 1 : Questions architecturales et d'outillage

**Q: Pourquoi KEDA plutôt qu'un HPA classique avec métriques personnalisées ? HPA v2 les supporte déjà.**

A: Bien qu'HPA v2 supporte les métriques personnalisées, cela nécessite de déployer et maintenir une infrastructure complexe Prometheus Adapter. KEDA est entièrement "plug-and-play" avec 60+ sources d'événements intégrées. Plus important encore, HPA natif ne peut pas descendre à zéro — il ne peut que descendre à 1. KEDA est le seul mécanisme qui permet une consommation de ressources véritablement nulle quand inactif.

---

**Q: VPA et HPA ne peuvent pas tous les deux toucher au CPU — comment mettre à l'échelle une app web sur le CPU tout en la dimensionnant correctement ?**

A: Nous découplons les métriques. Pour les apps web typiques, nous assignons HPA à gérer le CPU (gérant les pics de trafic imprévisibles par le scaling horizontal) et VPA à gérer la mémoire (right-sizing de l'empreinte de base dans le temps). Si nous devons dimensionner le CPU, nous utilisons le mode Initial de VPA — il évalue les demandes CPU seulement à la naissance du pod, puis passe le contrôle total au HPA.

---

**Q: Si le choix de l'autoscaler est fixé à la création du cluster, quel est le chemin de migration depuis Cluster Autoscaler vers Karpenter ?**

A: C'est une migration bleu-verte sécurisée. Karpenter peut fonctionner simultanément avec Cluster Autoscaler. Nous déployons Karpenter, introduisons un nouveau NodePool, puis taintons ou réduisons progressivement les anciens Managed Node Groups. Les workloads drainent naturellement de CAS et atterrissent sur le matériel provisionné par Karpenter sans recréation du cluster.

---

### Groupe 2 : Stabilité, rayon d'explosion et disponibilité

**Q: Consolidation Karpenter + mes PodDisruptionBudgets + interruptions spot — que devient ma disponibilité ?**

A: Les contrôles natifs Kubernetes toujours gagnent. Karpenter respecte strictement les budgets de disruption de pod. Si une consolidation ou une remplacement spot viole votre budget de disruption de pod, Karpenter annule le mouvement. Pour les workloads critiques, nous pouvons injecter `karpenter.sh/do-not-disrupt: "true"` pour verrouiller les pods à leur nœud actuel de façon permanente.

---

**Q: Quel est le rayon d'explosion / le scénario de rollback si VPA recommande une chose terrible en mode Initial ou InPlace ?**

A: Le rayon d'explosion est strictement contrôlé. Nous imposons des garde-fous avec les limites `minAllowed` et `maxAllowed` de VPA pour que les recommandations folles ne puissent jamais affamer ou gonfler un pod. Si une mauvaise mise à jour sort, le rollback est instantané : supprimez l'objet VPA ou changez son mode en Off, et encodez manuellement les dernières demandes de ressources stables dans votre manifeste de déploiement.

---

**Q: Latence cold start à zéro — combien c'est grave, et comment l'atténuer (keep-warm, min replicas) ?**

A: Le cold start est réel — typiquement 1-3 minutes si Karpenter doit provisionner un nœud brut à partir de zéro. Nous atténuons selon le niveau d'application : Les apps Tier-1 accédées par les clients sont interdites de descente à zéro (`minReplicas: 1`). Pour les workers async, nous acceptons le délai ou utilisons la marge de Karpenter pour garder de petits buffers de capacité pré-chauffée prête.

---

### Groupe 3 : Questions business et chronologie

**Q: Coût : le 20–40% est un chiffre marketing AWS. Qu'avons-nous mesuré ?**

A: Les chiffres marketing supposent une base pire cas. Dans nos tests, les économies dépendent fortement du profil de charge. Pour les environnements dev/test très variables et les workers événementiels, nous nous rapprochons de ce pourcentage [X]% grâce à la descente à zéro nocturne et la consolidation Karpenter. Pour les apps production à état stable, les économies sont moindres mais la stabilité s'améliore considérablement.

---

**Q: Chronologie — quand pourrai-je vraiment utiliser ceux-ci ?**

A: La Phase 1 (VPA en mode Recommendation/Off + Karpenter pour Non-Prod) est disponible [Date cible]. La Phase 2 (Full scaling automatisé et mises à jour In-Place pour Prod) est prévue pour [Date cible] après notre période de test.

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
5. <a href="https://github.com/Azure/karpenter-provider-azure/issues/1351">Issue Azure NAP #1351</a>
6. Guides d'utilisation VPA / KEDA et la proposition d'autoscaling Karpenter (docs-main)

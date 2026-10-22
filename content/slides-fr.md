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

---

<!-- VPA limitations -->
## VPA : quand NE PAS l'utiliser

![bg left:20%](./img/aurora.png)

- **Charges en pics :** VPA réagit à l'historique ; les pics soudains peuvent être sous-provisionnés
- **Applications JVM / réglées sur le tas :** changer la mémoire ne change pas `-Xmx` ; dimensionnez le runtime
- **Charges sensibles aux évictions :** évitez `Recreate` quand les redémarrages coûtent cher
- **Même ressource que KEDA :** ne laissez jamais deux contrôleurs se disputer la même ressource (voir Partie 4)
- **Processus très éphémères :** VPA a besoin de temps pour collecter et analyser les données d'utilisation

<br>

> **C'est l'axe 'quelle taille'.** Ensuite : KEDA décide *combien* de réplicas vous avez besoin.

---

<!-- ============================ PARTIE 2 : KEDA ============================ -->
<!-- Diviseur de section KEDA -->
# Partie 2 : KEDA
## Mise à l'échelle événementielle Kubernetes

![bg left:30%](./img/aurora.png)

### Mise à l'échelle des réplicas selon la demande réelle

KEDA intercepte l'**origine de la charge**—comme la profondeur de file ou les horaires cron—plutôt que d'attendre que vos serveurs surchauffent.

- **Descente à zéro :** Arrête en toute sécurité les apps inactives pour éviter de gaspiller le budget.
- **Hooks directs vers événements :** Intégration transparente avec Kafka, RabbitMQ et métriques.

<blockquote>
L'HPA standard surveille la conséquence de la charge (le CPU). KEDA surveille l'origine de la charge (les Événements).
</blockquote>

- **Orchestration pilotée par CRD :** Géré nativement via `ScaledObject` (pour les Deployments/StatefulSets) et `ScaledJob` (pour les boucles de traitement par lots éphémères)

<br>

<blockquote>
L'HPA standard surveille la conséquence de la charge (le CPU). KEDA surveille l'origine de la charge (les Événements).
</blockquote>

---

<!-- Architecture KEDA en profondeur -->
<!-- Architecture KEDA en profondeur -->
## Architecture de KEDA : Le moteur à double contrôleur

KEDA divise ses responsabilités en deux sous-systèmes afin de maintenir des performances élevées sans bloquer le plan de contrôle de votre cluster.

<div style="display: flex; justify-content: space-between; align-items: stretch; gap: 15px;">

  <!-- Column 1: Ingestion -->
  <div style="width: 30%; border: 1px dashed #777; padding: 10px; border-radius: 6px;">
    <div class="plate plate-head" style="background: #4A5568;">Sources de télémétrie</div>
    <div class="plate">Lag Kafka</div>
    <div class="plate">Profondeur RabbitMQ</div>
    <div class="plate">Requêtes Prometheus</div>
  </div>

  <div style="display: flex; align-items: center; font-size: 1.5em; color: #2d7d9a;">&rarr;</div>

  <!-- Column 2: 1 to N Engine -->
  <div style="width: 32%; background: rgba(45, 125, 154, 0.1); padding: 10px; border-radius: 6px;">
    <div class="plate plate-head" style="background: #2d7d9a;">KEDA Metrics Server</div>
    <div class="plate"><b>gestion de la montée 1 &rarr; N</b></div>
    <div class="plate">Agit comme fournisseur HPA v2</div>
    <div class="plate">HPA natif interroge toutes les 15s</div>
  </div>

  <!-- Column 3: 0 to 1 Engine -->
  <div style="width: 32%; background: rgba(45, 125, 154, 0.1); padding: 10px; border-radius: 6px;">
    <div class="plate plate-head" style="background: #2d7d9a;">KEDA Operator</div>
    <div class="plate"><b>gestion de la descente 0 &harr; 1</b></div>
    <div class="plate">Contourne les limites HPA native</div>
    <div class="plate">Modifie directement les réplicas pod</div>
  </div>

</div>

<br>

<blockquote>
Ingestion de télémétrie &rarr; Metrics Server (montée) + Operator (ravivage depuis zéro).
</blockquote>

</div>

<blockquote>
Metrics Server (pour la montée en charge) + Operator (pour la descente à zéro) = Mise à l'échelle zéro à N complète.
</blockquote>

---

<!-- Mécanismes du Scale-To-Zero KEDA -->
<!-- Mécanismes du Scale-To-Zero KEDA -->
## Scale-To-Zero avec KEDA : Comment ça fonctionne réellement

La mise à l'échelle à zéro nécessite une coordination approfondie car un HPA natif de Kubernetes ne peut pas évaluer un workload à `0` réplica.

<div style="display: flex; justify-content: space-between; align-items: stretch; gap: 10px; font-size: 0.85em;">

  <!-- Étape 1 -->
  <div style="width: 23%; background: rgba(0,0,0,0.03); padding: 10px; border-radius: 6px; border-top: 4px solid #718096;">
    <div style="font-weight: bold; color: #4A5568; margin-bottom: 5px;">1. Phase d'inactivité</div>
    <div style="font-size: 0.9em; line-height: 1.3;">
      Le workload est à <b>0 réplicas</b>. Sans pods actifs, l'HPA natif n'a plus de métriques et devient complètement inactif.
    </div>
  </div>

  <!-- Étape 2 -->
  <div style="width: 23%; background: rgba(0,0,0,0.03); padding: 10px; border-radius: 6px; border-top: 4px solid #2d7d9a;">
    <div style="font-weight: bold; color: #2d7d9a; margin-bottom: 5px;">2. Surveillance active</div>
    <div style="font-size: 0.9em; line-height: 1.3;">
      L' <b>opérateur KEDA</b> surveille. Il interroge indépendamment votre flux d'événements (ex: Kafka) toutes les <code>pollingInterval</code> secondes.
    </div>
  </div>

  <!-- Étape 3 -->
  <div style="width: 23%; background: rgba(0,0,0,0.03); padding: 10px; border-radius: 6px; border-top: 4px solid #2b6cb0;">
    <div style="font-weight: bold; color: #2b6cb0; margin-bottom: 5px;">3. Démarrage (kickstart)</div>
    <div style="font-size: 0.9em; line-height: 1.3;">
      Des événements arrivent ! L'opérateur réveille le workload, contourne l'HPA et patche directement <code>spec.replicas</code> de <b>0 à 1</b>.
    </div>
  </div>

  <!-- Étape 4 -->
  <div style="width: 23%; background: rgba(0,0,0,0.03); padding: 10px; border-radius: 6px; border-top: 4px solid #2f855a;">
    <div style="font-weight: bold; color: #2f855a; margin-bottom: 5px;">4. Passerelle des moteurs</div>
    <div style="font-size: 0.9em; line-height: 1.3;">
      Avec 1 pod actif, l'HPA s'active. Le <b>Metrics Server KEDA</b> gère la télémétrie et alimente l'HPA pour la montée en charge <b>1 &rarr; N</b>.
    </div>
  </div>

</div>

<br>

<blockquote>
L'opérateur réveille le workload ; le Metrics Server le met à l'échelle.
</blockquote>

    <div class="plate plate-head">Passage de relais (1 → N)</div>
    <div class="plate">Le Metrics Server alimente l'HPA pour la mise à l'échelle forte charge</div>
  </div>
</div>

---

<!-- Exemple de ScaledObject de production avancé -->
## KEDA : Exemple de Spec pour la Production (Enterprise-Grade)

Un `ScaledObject` de production doit contrôler les comportements de l'HPA en aval, les seuils de secours (fallback) et les mécaniques d'authentification.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: billing-processor-scaler
spec:
  scaleTargetRef:
    name: billing-processor-deployment
  pollingInterval: 15           # Fréquence d'interrogation du flux d'événements externe
  cooldownPeriod:  600          # Attend 10m avant d'exécuter la descente à 0
  minReplicaCount: 1            # Ligne de base en prod (Garantit l'absence de cold-start)
  maxReplicaCount: 50           # Plafond limite strict
  advanced:
    restoreToOriginalReplicaCount: true
    horizontalPodAutoscalerConfig:
      behavior:                 # Profils de stabilisation natifs de l'HPA
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
          - type: Percent
            value: 10           # Descente progressive (max 10% de réduction par étape)
            periodSeconds: 60
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: kafka.aurora.svc:9092
        topic: payment-events
        consumerGroup: billing-group
        lagThreshold: "10"      # Cible : 1 réplica par tranche de 10 messages non lus
```

---

<!-- Portfolio de déclencheurs de production -->
## Portfolio de déclencheurs de production sur Aurora

Ne limitez pas KEDA aux simples files d'attente de messages. Tirez parti des scalers alternatifs à l'échelle de l'entreprise.

- **Scaler Prometheus / Thanos :** Mettez à l'échelle vos microservices en fonction des taux d'erreur HTTP, de la vitesse des requêtes entrantes (RPS), ou des durées d'exécution des requêtes
- **Scaler Cron / Calendrier :** Préchauffez les clusters avant les heures de bureau. Combine avec `desiredReplicas` pour forcer des augmentations de charge avant la connexion des équipes le matin
- **Fallback CPU/Mémoire :** Oui, KEDA peut s'aligner sur les métriques de ressources système standard s'il est configuré comme déclencheur secondaire, offrant une sécurité si votre flux d'événements principal devenait inaccessible ou dégradé

---

<!-- Règles de sécurité et bonnes pratiques de production -->
## Règle Aurora : Authentification sécurisée de KEDA

N'authentifiez jamais les scalers via des chaînes de caractères en texte clair dans la spec. Liez toujours les déclencheurs à des cibles externes en utilisant les CRD `TriggerAuthentication` ou `ClusterTriggerAuthentication` connectés à des `SecretProviderClasses`.

---

<!-- Gardes-fous et rayon d'action KEDA -->
## Gardes-fous de production pour KEDA

### ⚠️ Scale-To-Zero en production
**Risque:** Réduire les API ou consommateurs critiques à 0 garantit 1-3 minutes de cold-start
**Atténuation:** `minReplicaCount: 1` pour Tier-1; réserver au non-prod ou workers async

### ⚖️ Ajustement fenêtre stabilisation
**Ne pas:** Contrôler scale-down avec `cooldownPeriod`
**Faire:** Utiliser `advanced.horizontalPodAutoscalerConfig.behavior` pour règles HPA

### 🛡️ Télémétrie & Observabilité
**Surveiller:** `keda_metrics_adapter_scaler_errors` Prometheus
**Alerte:** Expired broker credentials → panne silencieuse

---
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

<br>

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


---

<!-- Qu'est-ce qui pourrait mal tourner -->
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

---

<!-- Section FAQ déplacée vers faq-fr.md -->

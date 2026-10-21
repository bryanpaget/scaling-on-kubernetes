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

> **Note :** Aurora développe activement ces outils en tant que fonctionnalités de plateforme. KEDA est le plus avancé mais n'est pas encore activé par défaut.

<blockquote>
Des outils différents, des axes différents. La valeur est dans leur combinaison.
</blockquote>

---

<!-- Scaling axes map -->
## La carte de mise à l'échelle : trois axes

![bg left:20%](./img/aurora.png)

| Axe | Outil | Échelle | Niveau | Déclencheur |
|-----|-------|---------|--------|-------------|
| **Nombre de réplicas** | KEDA | Réplicas | Pod | Événements, files, horaires |
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

<!-- How the Recommender works -->
## Comment le Recommandeur fonctionne

![bg left:20%](./img/aurora.png)

Le Recommandeur est le "cerveau" fondamental de VPA. Il ne modifie pas votre cluster - il calcule et propose seulement des valeurs.

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">1. Surveillance continue</div>
    <div class="plate">Extrait des métriques en temps réel et historiques</div>
    <div class="plate">du Metrics Server/Prometheus</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">2. Analyse historique</div>
    <div class="plate">Moyenne mobile décroissante</div>
    <div class="plate">Les pics comptent le plus (pas d'OOM !)</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">3. Génère les cibles</div>
    <div class="plate">Borne inférieure, Cible, Borne supérieure, Cible sans plafond</div>
    <div class="plate">Écrit dans le statut VPA</div>
  </div>
</div>

> **Le Recommandeur propose seulement.** L'Updateur et le Contrôleur d'admission décident *quand* et *comment* appliquer les changements.

---

<!-- In-Place Resizing -->
## Redimensionnement en place : right-sizing sans interruption

![bg left:20%](./img/aurora.png)

VPA peut redimensionner les pods *sans éviction* avec le mode In-Place - mais cela nécessite des conditions spécifiques.

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">1. Recommandeur</div>
    <div class="plate">Calcule les nouvelles ressources</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">2. VPA met à jour</div>
    <div class="plate">Spécification du pod avec les nouvelles valeurs</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">3. Kubelet</div>
    <div class="plate">Met à jour les cgroups dynamiquement</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">4. App</div>
    <div class="plate">Utilise les nouvelles ressources instantanément</div>
  </div>
</div>

**Conditions pour zéro interruption :**
- **Support du runtime :** JVM/Node.js doivent lire les limites cgroup dynamiquement (pas seulement au démarrage)
- **Capacité du nœud :** Le nœud doit avoir des ressources de rechange
- **Risque de downscaling :** Réduire la mémoire trop agressivement peut déclencher des OOM

> **Pourquoi InPlaceOrRecreate ?** Si InPlace échoue (nœud plein, runtime non compatible), il tombe en sécurité sur eviction/recreate.

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
## VPA sur Aurora : statut d'adoption

![bg left:20%](./img/aurora.png)

| Paramètre | Valeur |
|-----------|--------|
| Version VPA | 1.7 (dernière ; appVersion 1.35+) |
| Espace de noms | vpa-system (en développement) |
| Metrics Server | Activé (requis) |
| Contrôleur d'admission | Activé (webhook mutateur) |
| Prometheus/ServiceMonitor | Désactivé (opt-in par workload) |

**Statut actuel :** Aurora développe VPA en tant que fonctionnalité de plateforme. L'implémentation est en cours mais pas encore activée par défaut.

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
- **Utiliser KEDA et votre propre HPA ensemble** - KEDA crée et gère l'HPA ; vous configurez seulement le ScaledObject
- **Vous fier à des cooldowns courts pour l'isolement** - `cooldownPeriod` (par défaut 300s) n'affecte que le passage final de zéro, pas la réduction générale (c'est la fenêtre `behavior` de HPA)

### FAIRE :
- Gardez `minReplicaCount: 1`+ en production (pas de descente à zéro)
- Ajoutez `terminationGracePeriodSeconds` pour les consommateurs longue durée
- Utilisez `ScaledJob` pour le traitement batch événementiel
- Validez sur un cycle complet de 24 heures en hors prod

> **Astuce :** Pensez à KEDA comme le service HPA - vous configurez ce qui doit être dimensionné (ScaledObject), KEDA gère le contrôleur HPA réel en coulisses.

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

<blockquote>
Apprenez Karpenter. Utilisez NAP du CSP s'il fonctionne. Revenez à l'auto-hébergé si des contraintes émergeaient.
</blockquote>

---

<!-- Karpenter limitations -->
## Karpenter : risques et mises en garde

![bg left:20%](./img/aurora.png)

- **Le fournisseur GCP est maintenu par la communauté :** le [CloudPilot AI shim](https://github.com/cloudpilot-ai/karpenter-provider-gcp) est pré-1.0 ; des changements cassants surviennent. Épinglez les versions, scannez, gardez l'Autoscaling GKE comme fallback
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
| **KEDA + HPA** | Ne configurez pas à la fois le ScaledObject de KEDA et votre propre HPA pour le même déploiement — KEDA crée et possède l'HPA sous-jacent automatiquement |
| **VPA + Karpenter** | Complémentaires : VPA change les demandes, Karpenter repack. Définissez `maxAllowed` et `limits` |
| **KEDA 0 + Karpenter** | Descente à zéro + consolidation vide et retire les nœuds. Attention au cold start |

> **Ce que "votre propre HPA" signifie :** Créer un manifeste HorizontalPodAutoscaler Kubernetes qui cible le même déploiement qu'un ScaledObject KEDA. Les deux autoscalers se battront sur le nombre de réplicas, causant des oscillations et des échafaudages d'API.

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

<!-- Good vs bad interactions -->
## Bonnes vs mauvaises interactions

![bg left:20%](./img/aurora.png)

| Scénario | Bon | Mauvais |
|----------|-----|---------|
| **Système de partage de vélos** (comme Hello Bike) | KEDA scale selon les événements de vélos, VPA dimensionne les pods, Karpenter ajoute des nœuds | HPA + KEDA sur la même métrique cause des oscillations |
| **Contrôle de drone swarm** | KEDA scale selon la profondeur de file, VPA dimensionne pour la mémoire, Karpenter ajoute des GPU | Pas de `limits` sur Karpenter → provisionnement incontrôlé |
| **Défense cyber** | KEDA scale selon les événements de menace, VPA dimensionne pour les pics CPU, Karpenter ajoute des nœuds | Descente à zéro en prod → latence de détection |
| **Général** | VPA (ressources) + KEDA (réplicas) + Karpenter (nœuds) = pipeline efficace | HPA + KEDA sur le même déploiement → oscillation |

> **Astuce :** KEDA crée et possède un HPA en coulisses. Ne créez pas votre propre HPA pour le même workload.

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

<!-- Q&A -->
## Questions ?

![bg left:20%](./img/aurora.png)

### Questions plus difficiles

**Q: Pourquoi KEDA plutôt qu'un HPA classique avec métriques personnalisées ? HPA v2 les supporte déjà.**

**Q: VPA et HPA ne peuvent pas tous les deux toucher au CPU — comment mettre à l'échelle une app web sur le CPU tout en la dimensionnant correctement ?**

**Q: Consolidation Karpenter + mes PodDisruptionBudgets + interruptions spot — que devient ma disponibilité ?**

**Q: Quel est le rayon d'explosion / le scénario de rollback si VPA recommande une chose terrible en mode Initial ou InPlace ?**

**Q: Si le choix de l'autoscaler est fixé à la création du cluster, quel est le chemin de migration depuis Cluster Autoscaler vers Karpenter ?**

**Q: Coût : le 20–40% est un chiffre marketing AWS. Qu'avons-nous mesuré ?**

**Q: Chronologie — quand pourrai-je vraiment utiliser ceux-ci ?**

**Q: Latence cold start à zéro — combien c'est grave, et comment l'atténuer (keep-warm, min replicas) ?**

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

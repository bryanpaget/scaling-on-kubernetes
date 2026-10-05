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
## La carte de mise à l'échelle : quatre axes

![bg left:20%](./img/aurora.png)

| Outil | Échelle | Niveau | Déclencheur |
|-------|---------|--------|-------------|
| **HPA** | Nombre de réplicas | Pod | CPU/mémoire/métriques |
| **VPA** | Demandes de ressources | Pod | Historique d'utilisation |
| **KEDA** | Réplicas (jusqu'à 0) | Pod | Événements, horaires, files |
| **Karpenter** | Nœuds | Infrastructure | Pods en attente |

<blockquote>
Les scalers de workload (HPA/VPA/KEDA) décident des besoins. Karpenter fournit la capacité.
</blockquote>

---

<!-- How they layer -->
## Comment ils s'empilent

![bg left:20%](./img/aurora.png)

<div class="flow">
  <div class="flow-box">
    <div class="plate plate-head">KEDA / HPA</div>
    <div class="plate">Crée ou retire des pods</div>
    <div class="plate">(nombre de réplicas)</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">VPA</div>
    <div class="plate">Fixe les demandes</div>
    <div class="plate">CPU / mémoire de chaque pod</div>
  </div>
  <div class="flow-arrow">&rarr;</div>
  <div class="flow-box">
    <div class="plate plate-head">Karpenter</div>
    <div class="plate">Provisionne les nœuds</div>
    <div class="plate">adaptés aux pods résultants</div>
  </div>
</div>

<blockquote>
Décisions de réplicas et de taille deviennent une demande de pods que Karpenter satisfait.
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

**Vertical Pod Autoscaler :** ajuste automatiquement les demandes CPU et mémoire de vos conteneurs

![bg left:20%](./img/aurora.png)

- Contrairement à HPA qui dimensionne les *réplicas*, VPA dimensionne les *demandes de ressources*
- Fonctionne avec Deployments, StatefulSets, DaemonSets
- Deux phases : Recommandeur (analyse) + Updateur (applique)
- Natif Kubernetes via les Custom Resource Definitions

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
- **Surveillance continue :** analyse les modèles d'utilisation réels
- **Ajustement automatique :** met à jour les demandes au fil du temps
- **Dimensionnement correct :** optimise l'utilisation du cluster

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
| Version VPA | 0.13.0 (appVersion 1.8.0) |
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
        controlledResources: ["cpu", "memory"]
```

**Les bornes comptent :** `maxAllowed` plafonne une recommandation excessive ; `minAllowed` garde les pods ordonnançables.

---

<!-- VPA limitations -->
## VPA : quand NE PAS l'utiliser

![bg left:20%](./img/aurora.png)

- **Charges en pics :** VPA réagit à l'historique ; les pics soudains peuvent être sous-provisionnés
- **Applications JVM / réglées sur le tas :** changer la mémoire ne change pas `-Xmx` ; dimensionnez le runtime
- **Charges sensibles aux évictions :** évitez `Recreate` quand les redémarrages coûtent cher
- **Jobs batch / éphémères :** utilisez KEDA Jobs ; VPA a besoin de temps pour observer
- **Même ressource que HPA/KEDA :** ne laissez jamais deux contrôleurs se disputer la même ressource (voir Partie 4)

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
| Version KEDA | 2.20.2 |
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
- **Descendre à zéro en production** - gardez `minReplicaCount: 1`+
- **Mélanger cron et CPU/mémoire** - le HPA prend le MAX, la mise à l'échelle devient imprévisible
- **Créer votre propre HPA** pour un workload géré par KEDA - KEDA le possède
- **Utiliser des cooldowns courts** - 300s+ en production

### FAIRE :
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
| Pré-provisionnement | Pool de nœuds entier | Un seul nœud adapté |
| Sélection d'instance | Premier SKU de la politique | Le moins cher qui convient |
| Consolidation | Pools vides seulement | Repack continu |
| Multi-famille | Pool statique | Plusieurs familles, spot + on-demand |
| Vitesse de provisionnement | Minutes | ~45-60s (benchmark fournisseur) |

> Réduction de coûts estimée de 20-40 % vs Cluster Autoscaler (benchmark externe - à valider en pilote).

---

<!-- Karpenter NodePool -->
## Karpenter : NodePool comme source de vérité

![bg left:20%](./img/aurora.png)

Définissez l'intention une fois ; déployez partout (AWS/Azure/on-prem nativement, GKE via le fournisseur CloudPilot).

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
spec:
  template:
    spec:
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
    cpu: "1000"
```

---

<!-- Karpenter Aurora -->
## Karpenter sur Aurora : le plan

![bg left:20%](./img/aurora.png)

- **Standard partout :** un seul modèle NodePool/NodeClaim sur AWS, Azure, on-prem, GKE
- **AWS / Azure / on-prem :** fournisseurs first-party (Karpenter v1 est GA)
- **GKE :** pas de fournisseur first-party ; via le fournisseur open-source CloudPilot AI GCP (mêmes APIs)
- **Fallback :** NAP GKE natif + Custom Compute Classes, gardé prêt si le fournisseur ne convient pas

> Le fournisseur GKE est pré-1.0 et communautaire : épinglez la version, scannez-le, gardez le fallback NAP. Pilotez avant toute bascule en production.

---

<!-- Karpenter limitations -->
## Karpenter : risques et mises en garde

![bg left:20%](./img/aurora.png)

- **Dépendance GKE :** le fournisseur CloudPilot est pré-1.0 ; des changements cassants surviennent (suivez `MIGRATION.md`)
- **Churn de nœuds :** une consolidation agressive perturbe les pods ; ajustez `consolidateAfter` et utilisez des PDB
- **Les chiffres de coûts sont des benchmarks**, pas des mesures Aurora ; établissez votre propre base d'abord
- **Changement de modèle :** le changement d'autoscaler se fait à la création du cluster, pas en cours de workload
- **Définissez `limits`** pour qu'un workload emballé ne provisionne pas de capacité illimitée

---

<!-- ============================ PARTIE 4: Interactions ============================ -->
<!-- Interactions divider -->
# Partie 4 : L'assemblage
## Interactions et anti-patrons

![bg left:30%](./img/aurora.png)

---

<!-- The combined picture -->
## L'image combinée

![bg left:20%](./img/aurora.png)

1. **KEDA / HPA** décident le nombre de réplicas selon événements ou horaires
2. **VPA** fixe les demandes CPU/mémoire de chaque pod selon l'historique
3. Ces pods deviennent une demande d'ordonnancement
4. **Karpenter** provisionne les nœuds les moins chers qui conviennent, puis consolide

<blockquote>
Nombre de réplicas x taille par pod = la demande de pods que Karpenter satisfait. Les trois alimentent un seul pipeline.
</blockquote>

---

<!-- Conflict rules -->
## Les règles qui les empêchent de se battre

![bg left:20%](./img/aurora.png)

| Paire | Règle |
|-------|-------|
| **VPA + HPA** | Jamais la même ressource. VPA = mémoire, HPA = CPU (`controlledResources`) |
| **VPA + KEDA** | Même règle : KEDA est un HPA en dessous, donc séparez la ressource |
| **KEDA + votre HPA** | Ne créez pas votre propre HPA ; KEDA le possède (`transfer-hpa-ownership` au besoin) |
| **VPA + Karpenter** | Complémentaires : VPA change les demandes, Karpenter repack. Définissez `maxAllowed` et `limits` |
| **KEDA 0 + Karpenter** | Descente à zéro + consolidation vide et retire les nœuds. Puissant, mais attention au cold start |

---

<!-- Anti-patterns -->
## Anti-patrons à éviter

![bg left:20%](./img/aurora.png)

- **VPA et HPA/KEDA sur la même métrique** - ils oscillent l'un contre l'autre
- **VPA `Recreate` sur des workloads sensibles aux évictions** - préférez Initial/InPlace
- **Descente à zéro en production** sans tenir compte du cold start
- **Pas de `maxAllowed` / pas de `limits` NodePool** - une mauvaise recommandation peut demander un nœud entier, et Karpenter le provisionnera
- **Consolidation agressive sans PDB** - le churn de nœuds perturbe les workloads

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

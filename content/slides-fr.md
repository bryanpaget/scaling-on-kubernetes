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
## Vertical Pod Autoscaling

---

<!-- What is VPA -->
## Qu'est-ce que VPA ?

**Vertical Pod Autoscaler** ajuste les demandes et limites CPU/mémoire des pods selon l'utilisation observée.

- **Cibles :** demandes et limites CPU/mémoire
- **Workloads :** Deployments, StatefulSets, DaemonSets
- **Fonctionnement :** Recommandeur analyse → Updateur applique → Contrôleur d'admission mutate à la naissance

<br>

<blockquote>
L'HPA met à l'échelle combien, VPA met à l'échelle quelle taille.
</blockquote>

---

<!-- Pourquoi VPA -->
## Pourquoi VPA

Le piège de la base statique : valeurs génériques codées en dur au déploiement.

**Mode `Initial` :** Injecteur intelligent à la naissance, risque zéro à l'exécution.

- Mutation à la naissance : Contrôleur d'admission intercepte avant planification
- Profils plutôt que devinettes : Valeurs basées sur l'historique d'utilisation
- Zéro churn : Ressources verrouillées une fois en cours d'exécution

<br>

<blockquote>
Verrouillez l'empreinte optimale dès le jour zéro, sans risque runtime.
</blockquote>

---

<!-- ============================ PARTIE 2 : KEDA ============================ -->
<!-- Diviseur de section KEDA -->
# Partie 2 : KEDA
## Mise à l'échelle événementielle Kubernetes

![bg left:30%](./img/aurora.png)

---

<!-- What is KEDA -->
## Qu'est-ce que KEDA ?

Mettre à l'échelle sur événements, pas seulement sur CPU/mémoire.

- **Relie** les systèmes externes (Kafka, Redis, files) à l'HPA natif
- **Descente à zéro** — méthode standard pour amener un workload à zéro
- **Piloté par les CRD** — `ScaledObject` pour deployments, `ScaledJob` pour batches
- **Deux contrôleurs** — Opérateur gère 0↔1, Metrics Server gère 1→N

<br>

<blockquote>
L'HPA surveille la conséquence de la charge (le CPU). KEDA surveille son origine (les événements).
</blockquote>

---

<!-- ScaledObject Example -->
## ScaledObject : La configuration

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: threat-analyzer-scaler
spec:
  scaleTargetRef:
    name: threat-analyzer
  pollingInterval: 1            # Redis interrogé chaque seconde
  cooldownPeriod: 15            # Maintien avant descente à zéro
  minReplicaCount: 0            # Descente réelle à zéro
  maxReplicaCount: 10           # Plafond maximal
  triggers:
  - type: redis
    metadata:
      address: redis-service:6379
      listName: security-alerts
      listLength: "5"           # Cible : 5 éléments par réplica
      activationListLength: "1" # Réveil à zéro dès le premier élément
```

---

<!-- Leçon réseau -->
## Polices réseau : Critique pour KEDA

**Dans les clusters Cilium, l'opérateur KEDA a besoin de politiques d'égress explicites pour interroger les sources de déclenchement:**

```yaml
# Autoriser l'opérateur KEDA à atteindre les sources de déclenchement
- fromEndpoints:
    - matchLabels: app: keda-operator
  toEndpoints:
    - matchLabels: <source-declenchement>
  toPorts:
    - port: "<port-source>"
```

**Pourquoi c'est important:** L'autoscaling peut paraître sain alors que le trafic de déclenchement est bloqué. Vérifiez la connectivité de bout en bout — l'opérateur interroge les déclencheurs, pas l'HPA.

**Pattern dans différents environnements:**
- **Aurora:** Polices globales au niveau du cluster + politiques Cilium par application
- **Autres environnements:** Pattern similaire, configuration réseau adaptée à la plateforme
- **Clé:** Assurez-vous que l'opérateur KEDA peut atteindre toutes les sources de déclenchement (Redis, Kafka, Prometheus, etc.)

---

<!-- Portfolio de déclencheurs de production -->
## Types de déclencheurs en production

KEDA supporte plusieurs types de scalers au-delà des files Redis:

| Type | Cas d'usage |
|------|-------------|
| **Prometheus** | Mettre à l'échelle sur le débit, les taux d'erreurs, la latence |
| **Cron** | Préchauffe avant des plages horaires connues |
| **Kafka** | Workloads de streaming d'événements |
| **Azure Service Bus** | Files d'attente d'entreprise |
| **AWS SQS** | Files d'attente natives cloud |

---

<!-- Démo Redis KEDA -->
## Démo Redis KEDA : Mise à l'échelle événementielle

**Configuration:**
- File Redis stocke les signaux de sécurité des capteurs
- Générateur pousse des messages en vagues (10-50 tous les 5s, puis pause de 60s tous les 10 vagues)
- Workers de l'analyseur de menaces consomment les messages
- KEDA met à l'échelle les workers selon la profondeur de file

---

<!-- Live Demo: Rafale 500 éléments -->
## Démo: Rafale 500 éléments → Montée → Descente

```bash
kubectl exec -n keda-system \
  $(kubectl get pod -n keda-system -l app=redis -o jsonpath='{.items[0].metadata.name}') \
  -- sh -c 'i=1; while [ $i -le 500 ]; do redis-cli RPUSH security-alerts demo-$i; i=$((i+1)); done'
```

- Envoyer 500 items instantanément
- La file monte en flèche → les workers montent en charge
- Les workers vidagent le backlog
- La file atteint zéro → cooldown → remise à l'échelle vers zéro

---

<!-- ============================ PARTIE 3 : Karpenter ============================ -->

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

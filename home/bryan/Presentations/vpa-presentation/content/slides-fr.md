---

<!-- Overview -->
## Ce que couvre ce guide

![bg left:20%](./img/aurora.png)

Dimensionnement des nœuds sur Aurora : évaluation de Karpenter comme implémentation de référence et évaluation Azure

- **Karpenter** - provisionnement de nœuds juste-à-temps agnostique
- **AKS Node Auto Provisioning (NAP)** - offre gérée Azure basée sur Karpenter
- **Cluster Autoscaler** - baseline actuel, reste en production

<blockquote>
Nous avons besoin d'une expertise Karpenter quel que soit le choix final par cloud. Construisez une référence, testez les options Azure.
</blockquote>

---

<!-- La proposition -->
## Proposition d'apprentissage Karpenter et évaluation Azure

![bg left:20%](./img/aurora.png)

**Objectif :** Construire Karpenter comme référence inter-plateforme Aurora, en commençant par l'évaluation Azure

**Deux résultats :**
1. Référence et méthode indépendantes de la plateforme : conception NodePool, disruption, observabilité, runbooks
2. Recommandation Azure fondée sur des preuves : rester sur Cluster Autoscaler, adopter AKS NAP, ou auto-héberger Karpenter

**Ce qui est couvert :**
- Concepts, APIs, comportement opérationnel, modes d'échec Karpenter
- Référence auto-hébergée Karpenter sur Azure
- Pilote AKS NAP
- Comparaison trois-voies contre Cluster Autoscaler

**Ce qui n'est pas décidé :**
- Autoscaler unique pour AWS, Azure, GKE, on-prem
- Migration production
- Économies (mesures de baseline nécessaires)

---

<!-- Platform status -->
## Statut des plateformes

| Plateforme | Statut actuel | En portée | Prochaine étape |
|------------|---------------|-----------|-----------------|
| **Azure (AKS)** | En production ; Cluster Autoscaler | Référence auto-hébergée + pilote AKS NAP | Décision par [date] |
| **AWS** | Supporté dans le chart platform ; pas de clusters | Option séparée | Évaluer par [date] |
| **GKE** | Direction architecturale | Décision séparée | Évaluation des risques par [date] |
| **On-prem** | Direction architecturale | Auto-hébergé le plus important | Réévaluer par [date] |

**Pourquoi Azure en premier :**
- Plateforme de production actuelle d'Aurora
- Option Karpenter gérée existe (NAP)
- Fournisseur auto-hébergé première-vérité disponible

> **Note terminologique :** AKS NAP (Azure) et GKE NAP NE SONT PAS la même chose. Ce document utilise les noms préfixés partout.

---

<!-- Recommendation -->
## Recommandation

### 0. Vérifier l'éligibilité d'abord

Avant de construire quoi que ce soit, confirmer que les clusters AKS Aurora peuvent utiliser AKS NAP :
- Compatibilité CNI Cilium géré
- Exigences de fonctionnalités
- Incompatibilité avec Cluster Autoscaler sur le même cluster

Si NAP n'est pas viable, le pilote se limite à Karpenter auto-hébergé vs Cluster Autoscaler.

### 1. Construire la référence auto-hébergée Azure

Déployer Karpenter auto-hébergé sur un cluster AKS non-production séparé pour apprendre :
- Définitions NodePool et NodeClass
- Contraintes, limites, types de capacité, politiques de disruption
- Comportement de provisionnement, consolidation, remplacement, échec
- Métriques, logs, alertes, rapport de coût
- Identité, quotas, upgrades, rollback, capacité d'urgence

### 2. Piloter AKS NAP

Pilote AKS NAP sur un cluster non-production séparé. NAP est géré par Microsoft et basé sur Karpenter, mais Microsoft contrôle les composants gérés, le calendrier de versions, les opérations de cycle de vie.

### 3. Comparer trois options

Comparer **Cluster Autoscaler (baseline)**, **Karpenter auto-hébergé**, et **AKS NAP** en utilisant des profils de charge identiques. Ne jamais exécuter deux autoscalers sur le même cluster ou workload.

### 4. Prendre une décision Azure basée sur des preuves

- **Adopter AKS NAP** s'il répond aux critères et les compromis gérés sont acceptables
- **Adopter Karpenter auto-hébergé** si NAP a des lacunes et Karpenter répond aux critères
- **Rester sur Cluster Autoscaler** si aucune ne démontre un bénéfice suffisant

---

<!-- What transfers -->
## Ce qui se transfère entre plateformes

| Se transfère | Ne se transfère pas |
|--------------|---------------------|
| Contraintes, limites, logique type-capacité NodePool | Définitions NodeClass (spécifiques au fournisseur) |
| Budgets de disruption, consolidation, comportement drift | Images de nœud, chemin de démarrage, mécanique de patch d'image |
| Interaction avec PDBs, VPA, KEDA, descente à zéro | Identité cloud, permissions, gestion de quota |
| Approche métriques, alertes, dépannage | Disponibilité SKU et contraintes régionales |
| Méthode d'évaluation et critères d'acceptation | Limites de support service géré et cadence de publication |

**Insight clé :** Les résultats Azure ne se transfèrent pas aux autres plateformes. Chaque cloud nécessite sa propre évaluation.

---

<!-- How it works -->
## Comment fonctionne le dimensionnement de nœuds : Image complète

![bg left:20%](./img/aurora.png)

1. **Workload** - pods avec demandes de ressources, PDBs, contraintes
2. **Ordonnanceur** - ne peut pas placer les pods en attente en raison de la capacité
3. **Autoscaler** (CA ou Karpenter)
   - CA : ajoute un nœud à un pool prédéfini
   - Karpenter : provisionne un seul nœud qui convient au pod
4. **Nœud** démarre, tire les images, devient prêt
5. **Pod** est ordonnancé sur le nouveau nœud

**Important :** Le temps de démarrage du nœud (tirage d'image, démarrage) est séparé du provisionnement de l'autoscaler. Changer de contrôleurs ne crée pas de capacité chaude ou ne supprime pas la latence de tirage d'image.

---

<!-- Karpenter vs Cluster Autoscaler -->
## Pourquoi Karpenter plutôt que Cluster Autoscaler

| Aspect | Cluster Autoscaler | Karpenter |
|--------|-------------------|-----------|
| Provisionnement de nœuds | Ajoute des nœuds un par un à un groupe | Provisionne un seul nœud adapté à chaque pod en attente |
| Sélection d'instance | Utilise des expanders (least-waste, price, priority) | Choisit le type d'instance le moins cher qui convient |
| Consolidation | Supprime les nœuds sous-utilisés après drainage | Repack et suppression de nœuds continus |
| Multi-famille | Pool statique par groupe | N'importe quelle famille, spot + on-demand mélangés |
| Vitesse de provisionnement | Minutes | ~45-60s (benchmark fournisseur) |

> **Réduction de coûts estimée de 20-40 % vs Cluster Autoscaler** ([étude de cas AWS](https://repost.aws/articles/AR5C03QTEyRgKoDI-XO5UC7w/optimizing-your-amazon-eks-compute-costs-with-karpenter)) - valider en pilote Aurora.

---

<!-- NodePool -->
## Karpenter : NodePool comme source de vérité

![bg left:20%](./img/aurora.png)

Définissez l'intention de calcul une fois ; adaptez le `nodeClassRef` spécifique au fournisseur par plateforme (EC2NodeClass, AKSNodeClass, GKENodeClass, etc).

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        name: default
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30m
  limits:
    cpu: "1000"
```

**Concepts clés :**
- `NodePool` - source de vérité Aurora pour le dimensionnement de nœuds
- `NodeClass` - spécifique au fournisseur (EC2NodeClass, AKSNodeClass, etc)
- `limits` - prévenir le provisionnement incontrôlé
- `consolidateAfter` - ajuster à la tolérance au churn de charge

---

<!-- Why self-hosted -->
## Pourquoi auto-héberger Karpenter quand possible

**Objectif :** Construire une expertise Karpenter interne pour l'utiliser entre clouds

- **AWS :** Karpenter auto-hébergé (v1 GA, contrôle total)
- **Azure :** Essayer AKS NAP (géré) ; basculer vers auto-hébergé si des contraintes apparaissent
- **GKE :** Karpenter auto-hébergé (via CloudPilot AI shim)
- **On-prem :** Karpenter auto-hébergé (vous possédez l'infrastructure)

**Pourquoi auto-hébergé :**
- Mêmes APIs NodePool sur toutes les plateformes
- Contrôle complet des versions et balayage de sécurité
- Évite la manipulation des coûts par le CSP
- Liberté de migration si la solution CSP ne répond pas aux objectifs

**Compromis Azure NAP :** Simplicité gérée maintenant, mais risque de verrouillage du fournisseur plus tard.

---

<!-- Risks -->
## Karpenter : risques et mises en garde

| Plateforme | Risque | Mitigation |
|------------|--------|------------|
| **GCP** | Le fournisseur est maintenu par la communauté (pré-1.0) | Épingler les versions, scanner, garder l'Autoscaling GKE comme fallback |
| **Toutes** | Churn de nœuds de consolidation agressive | Ajuster `consolidateAfter`, utiliser PodDisruptionBudgets |
| **Azure** | Risque de verrouillage du fournisseur NAP | Inclure observabilité, dépannage, test de sortie dans les critères |
| **Toutes** | Le changement de modèle est à la création du cluster | Apprendre Karpenter d'abord, choisir NAP CSP seulement s'il fonctionne |

> Apprenez Karpenter. Utilisez NAP CSP s'il fonctionne. Revenez à auto-hébergé si des contraintes émergent.

---

<!-- Evaluation design -->
## Conception de l'évaluation

### Baseline (Cluster Autoscaler)

Enregistrer le comportement actuel :
- Latence du pod en attente à l'ordonnancement
- Latence de provisionnement et de préparation du nœud
- Temps de tirage d'image après la préparation du nœud
- Utilisation du nœud et capacité demandée
- Comportement de réduction d'échelle et de disruption
- Coût d'infrastructure par fenêtre de test
- Événements d'échec, quota, et ordonnancement

### Cas de test

1. Service stateless avec demande prévisible
2. Charge bursty créant des pods en attente
3. Workload avec taints, tolerations, affinité stricts
4. Workload protégé par un PDB
5. Workload avec grandes images ou hooks de démarrage lents
6. Workload exercant la réduction d'échelle et la consolidation
7. **Workload KEDA-scaled** (descente à zéro, montée à partir de zéro)
8. **Workload VPA-managed** (les demandes changent après l'ordonnancement)
9. **Stockage zonal** (PV avec affinité zone, overhead DaemonSet)
10. **Événements de cycle de vie de nœud** (patch d'image, drift, expiration)

KEDA et VPA sont des capacités planifiées d'Aurora ; les inclure pour que l'évaluation couvre l'état cible.

---

<!-- Acceptance criteria -->
## Critères d'acceptation

Les seuils doivent être définis **avant le début des tests** :

| Domaine | Preuve requise | Seuil |
|---------|----------------|-------|
| Provisionnement | Les nœuds deviennent disponibles pour toutes les contraintes | [>= 99 % de réussite] |
| Latence | Prêt-en-attente sous charge | [p95 <= X secondes] |
| Consolidation | Aucune violation PDB à travers N événements | [zéro violation] |
| Configuration | Labels, taints, images, zones, SKUs supportés | [tous requis] |
| Observabilité | Métriques, alertes, logs supportent le dépannage | [toutes les alertes déclenchent] |
| Opérations | Upgrades, rollback, procédures d'incident testées | [chacune exécutée] |
| Sécurité | Revue PBMM par option | [selon revue sécurité Aurora] |

**La sécurité diffère par option :**
- Auto-hébergé : identité de contrôleur moindre privilège et permissions de nœud
- AKS NAP : auditer les permissions du contrôleur géré Microsoft et le gestion des données

---

<!-- Timeline -->
## Calendrier, effort, et propriété

| Élément | Valeur |
|---------|--------|
| Durée totale | [ex., 10-12 semaines, time-boxed] |
| Équipe et allocation | [noms/rôles, % allocation] |
| Coût estimé d'infrastructure | [coût du cluster non-production] |
| Date de décision | [date] |

---

<!-- Startup behavior -->
## Démarrage versus comportement d'autoscaler

Le pilote doit séparer le comportement d'autoscaler du démarrage du nœud :

- **Latence de provisionnement** - contrôleur voit le pod en attente au nœud en cours de création
- **Latence de démarrage du nœud** - nœud démarre, tire les images, devient prêt
- **Latence d'ordonnancement** - pod ordonnancé sur le nœud prêt

Changer de contrôleurs ne crée pas de capacité chaude ou ne supprime pas la latence de tirage d'image. Traiter le temps de démarrage comme une **variable mesurable par option**, pas une supposition.

Si Aurora nécessite une tête chaude, évaluer séparément : pool statique chaud, pods de sur-provisionnement de basse priorité, tirage d'image pré-charge, ou capacité minimum explicite.

---

<!-- Expected deliverables -->
## Livrables attendus

- Configuration de référence Karpenter auto-hébergé versionnée (source de vérité d'Aurora)
- Configuration du pilote AKS NAP et notes d'exploitation
- Mesures baseline et comparaison trois-voies
- Tableaux de bord, alertes, et runbooks de dépannage
- Procédures documentées d'upgrade, rollback, patch d'image, et sortie
- Méthode d'évaluation réutilisable pour les autres plateformes
- Recommandation Azure soutenue par des preuves pilotes

---

<!-- Conclusion -->
## Conclusion

Aurora a besoin d'une référence Karpenter qu'elle possède parce que :

- Les options basées sur Karpenter émergent sur Azure, AWS, et autres
- On-prem n'aura pas d'alternative gérée

Une évaluation Azure time-boxée :
- Construit la référence Karpenter d'Aurora
- Produit une méthode réutilisable
- Donnne à Azure une réponse fondée sur des preuves

Aurora reste adaptable : où un cloud offre Karpenter géré (comme AKS NAP), cela vaut la peine d'essayer précisément parce que l'équipe comprendra ce qui se trouve dessous.

Le résultat peut être :
- **AKS NAP** - Karpenter géré, défaut pragmatique
- **Karpenter auto-hébergé** - contrôle total, référence inter-plateforme
- **Rester sur Cluster Autoscaler** - si aucune ne démontre un bénéfice suffisant

Dans chaque cas, Aurora comprendra pourquoi.

---

<!-- References -->
## Références

### Amont :
1. <a href="https://karpenter.sh/docs/">Documentation Karpenter</a>
2. <a href="https://karpenter.sh/docs/concepts/">Concepts Karpenter</a>
3. <a href="https://github.com/kubernetes-sigs/karpenter">Karpenter upstream</a>
4. <a href="https://github.com/Azure/karpenter-provider-azure">Fournisseur Azure Karpenter</a>

### Azure :
5. <a href="https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning">AKS Node Auto Provisioning</a>
6. <a href="https://docs.aws.amazon.com/eks/latest/best-practices/automode.html">AWS EKS Auto Mode</a>
7. <a href="https://cloud.google.com/kubernetes-engine/docs/concepts/node-auto-provisioning">GKE Node Auto-Provisioning</a>

### Plateforme Aurora :
8. <a href="https://github.com/gccloudone-aurora/aurora-platform-charts">Aurora Platform Charts</a>

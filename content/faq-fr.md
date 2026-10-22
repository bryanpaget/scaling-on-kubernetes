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


### Amont :
1. <a href="https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/README.md">VPA (kubernetes/autoscaler)</a>
2. <a href="https://keda.sh/docs/">Documentation KEDA</a>
3. <a href="https://karpenter.sh/">Documentation Karpenter</a>

### Plateforme Aurora :
4. <a href="https://github.com/gccloudone-aurora/aurora-platform-charts">Aurora Platform Charts</a>
5. <a href="https://github.com/Azure/karpenter-provider-azure/issues/1351">Issue Azure NAP #1351</a>
6. Guides d'utilisation VPA / KEDA et la proposition d'autoscaling Karpenter (docs-main)

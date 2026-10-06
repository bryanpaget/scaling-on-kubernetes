---

title: "Aurora Karpenter Proposal"
subtitle: "Pourquoi Aurora devrait apprendre Karpenter, et quand utiliser une version gérée à la place"
date: "2026-10-06"
version: "v2.1 - Draft"

---

## L'enjeu

![bg left:20%](./img/aurora.png)

Aurora devrait apprendre Karpenter correctement et maintenir une petite implémentation de référence qu'elle exécute et comprend elle-même.

Ce n'est pas un argument pour auto-héberger Karpenter partout. Dans certains cas, Aurora n'aura aucun autre choix que de l'exécuter directement, et dans d'autres, un fournisseur cloud propose une version gérée qui est en réalité Karpenter en dessous.

L'implémentation de référence est ce qui permet à Aurora de distinguer ces cas et d'évaluer un service géré sur la base de preuves plutôt que sur la parole du fournisseur.

---

## Pourquoi cela compte

![bg left:20%](./img/aurora.png)

**La première raison :** Certaines plateformes ne laissent aucun choix. En on-premises et sur tout cloud sans offre Karpenter gérée, si Aurora veut le provisionnement juste-à-temps et la consolidation de Karpenter, elle doit l'exécuter elle-même.

**La deuxième raison :** D'autres plateformes offrent à Aurora une version gérée gratuitement. Azure Node Auto Provisioning (NAP) est l'autoscaler géré basé sur Karpenter pour AKS, et AWS propose une voie comparable avec EKS Auto Mode.

**La troisième raison :** Un service géré n'est un bon marché que s'il se comporte comme il le devrait, et Aurora ne peut pas l'évaluer de l'extérieur.

---

## Ce qu'Aurora devrait faire

![bg left:20%](./img/aurora.png)

1. **Commencer :** Apprendre Karpenter et monter une petite implémentation auto-hébergée sur un cluster Azure (AKS) non-production.

2. **Comparer :** Essayer Azure NAP sur un cluster non-production séparé et comparer les deux directement.

3. **Décider :** Si NAP répond aux attentes, l'utiliser. Sinon, exécuter Karpenter auto-hébergé sur Azure.

La même expertise s'applique à l'on-premises (où l'auto-hébergement est la seule option) et aux autres clouds au fur et à mesure que leurs stratégies d'autoscaling mûrissent.

---

## Ce que ce n'est pas

![bg left:20%](./img/aurora.png)

- Cette proposition ne committe pas Aurora à auto-héberger Karpenter partout.
- Elle ne met pas Karpenter en production avant la comparaison Azure.
- Elle ne règle pas le choix pour AWS, GKE ou on-premises. Ceux-ci viendront plus tard et pourront réutiliser ce qu'Aurora apprend sur Azure.

---

## État actuel

![bg left:20%](./img/aurora.png)

- Aurora fonctionne aujourd'hui sur Azure (AKS) et utilise Cluster Autoscaler pour la mise à l'échelle des nœuds.
- AWS est supporté dans le chart plateforme, tandis que GKE et on-premises restent des directions architecturales plutôt que des systèmes en production.
- Passer de Cluster Autoscaler à un autoscaler conscient de la charge, que ce soit NAP ou Karpenter, est déjà sur la feuille de route d'efficacité compute (élément B de l'étape 2).
- Le choix entre les deux est encore ouvert.

**Une vérification pratique en premier :** Les clusters AKS d'Aurora utilisent Cilium géré. Avant tout essai, confirmer si NAP supporte cette configuration.

---

## Une mise en garde

![bg left:20%](./img/aurora.png)

Un autoscaler décide quand ajouter de la capacité et quelle forme cette capacité doit prendre. Il ne rend pas un nœud froid plus rapide à démarrer.

Un nœud nouvellement provisionné doit toujours démarrer et tirer les images, qu'il ait été demandé par Cluster Autoscaler, Karpenter auto-hébergé, ou NAP.

Si Aurora a besoin d'une marge chaude pour absorber les pics, il s'agit d'un travail séparé (une petite marge chaude ou des pods de remplissage basse priorité), et non une raison de préférer un autoscaler à un autre.

L'essai devrait garder cette ligne claire lorsqu'il mesure le temps de démarrage, afin que la comparaison reste honnête.

---

## Références

![bg left:20%](./img/aurora.png)

- Feuille de route d'efficacité compute (élément B de l'étape 2) : ../../roadmap/roadmap.md
- Karpenter : https://karpenter.sh/docs/
- Fournisseur Azure Karpenter et comparaison NAP : https://github.com/Azure/karpenter-provider-azure
- AKS Node Auto Provisioning : https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning
- AWS EKS Auto Mode : https://docs.aws.amazon.com/eks/latest/best-practices/automode.html

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.svg">
    <img alt="Perpetua : ingénierie autonome continue pour Claude Code" src="assets/banner-light.svg" width="100%">
  </picture>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="https://koffih.github.io/perpetua/">Documentation (anglais)</a>
</p>

---

**Perpetua fait avancer un projet logiciel pendant que personne n'est au clavier.** Il lance une session [Claude Code](https://claude.com/claude-code) neuve et sans surveillance sur votre dépôt, la laisse avancer dans votre plan pendant des heures, enregistre ce qu'elle a fait, attend, puis lance la suivante. Nuit après nuit, sans démon, sans clé d'API, et sans jamais travailler en même temps que vous.

Chaque session franchit cinq contrôles d'admission appliqués par le code, reçoit une consigne permanente qui vous appartient, et laisse un enregistrement lisible par une machine et un rapport lisible par un humain. La planification est confiée à systemd.

## Points forts

- **Contexte neuf, état durable** : chaque session repart d'un contexte vide et reconstruit sa compréhension depuis le dépôt (plan, notes d'avancement, historique git, demandes de fusion).
- **Garde-fous dans le code** : arrêt, verrou, pause après limite d'utilisation, présence de l'opérateur, question en attente. `--force` ne contourne jamais les trois premiers.
- **Attentif à l'opérateur** : si vous avez utilisé Claude Code dans les dix dernières minutes, Perpetua attend. Ses propres sessions sont reconnues et ignorées.
- **Une question, puis on continue** : une décision qui vous revient est écrite une seule fois dans le plan ; la session continue sur le travail indépendant, et les suivantes sont espacées pour ne pas brûler votre quota.
- **Natif systemd** : un service et un minuteur modèles par projet, journald, fonctionnement hors session grâce au lingering.
- **Sur votre abonnement** : utilise la connexion Claude Code existante, aucune clé d'API facturée au jeton.

## Démarrage rapide

```bash
curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash
perpetua doctor
perpetua init ~/work/atlas                  # configuration et .perpetua/directive.md
perpetua run atlas --force                  # une session supervisée
perpetua enable atlas --interval 30min      # la cadence : 30 min après chaque session
loginctl enable-linger "$USER"
```

Le matin :

```bash
perpetua status
perpetua summaries atlas
perpetua logs atlas
perpetua pause atlas        # reprise : perpetua resume atlas
```

## Sur un VPS

En root, sur un serveur Debian, Ubuntu ou Fedora neuf, depuis l'archive décompressée :

```bash
./platform/vps/bootstrap.sh --oauth-token-file claude-token --repo git@github.com:vous/atlas.git
```

Le script crée un compte dédié `perpetua`, active le lingering, installe Claude Code, Perpetua et le skill `autonomous-mode`, range le jeton obtenu par `claude setup-token` dans un fichier protégé (mode 600), génère une clé SSH à déclarer comme clé de déploiement, puis clone et enregistre le projet. `--dry-run` montre tout sans rien modifier. Voir le [guide VPS](https://koffih.github.io/perpetua/guides/vps/).

## Sous WSL2

Windows éteint la distribution quand aucun client WSL n'est ouvert, ce qui arrête les minuteurs. `platform/wsl/install-keepalive.ps1` installe un client invisible au démarrage de Windows. Voir le [guide WSL](https://koffih.github.io/perpetua/guides/wsl/).

## Licence

Copyright 2026 The Perpetua Authors. Sous [licence Apache 2.0](LICENSE). Claude et Claude Code sont des produits d'Anthropic ; Perpetua est un projet indépendant, non affilié à Anthropic.

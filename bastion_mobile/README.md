# Bastion mobile

Application Android de Bastion : affiche l'interface Bastion de votre instance en plein ecran
(connexion Keycloak, messages, salons, appels), avec camera/micro autorises pour les appels.

- Adresse par defaut : `https://bastion-secure.group` (modifiable : ecran **Serveur**, via « Changer de serveur » si l'instance est injoignable).
- Le navigateur integre s'annonce avec `BastionMobile/0.2` : l'administration voit « Appli mobile » dans l'onglet Connexions.
- HTTPS obligatoire, aucun certificat de test accepte.

## Fabriquer l'APK (sans ordinateur)
GitHub -> onglet **Actions** -> **APK Bastion** -> **Run workflow** (choisir la branche) -> a la fin, telecharger l'artefact `bastion-apk`.

## Etapes suivantes
Notifications d'appel et de message (appli fermee), appel natif, biometrie.

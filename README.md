# MadaGrossiste

Marketplace B2B pour les commerçants à Madagascar. Le site est publié comme un site statique sur Netlify ; les endpoints `/api/config` et `/api/chat` sont des fonctions Netlify.

## Configuration Netlify

Définir les variables suivantes dans **Site configuration → Environment variables** :

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY` (clé publique `sb_publishable_…`) ou `SUPABASE_ANON_KEY` (clé legacy dont le rôle JWT est `anon`)
- `AI_PROVIDER` (facultatif, `openai` par défaut ; mettre `gemini` pour utiliser Google Gemini)
- `OPENAI_API_KEY` (secret serveur, ne jamais l’ajouter au code frontend)
- `OPENAI_MODEL` (facultatif, défaut : `gpt-4o-mini`)
- `GEMINI_API_KEY` (secret serveur, requis lorsque `AI_PROVIDER=gemini` ; ne jamais l’ajouter au code frontend)
- `GEMINI_MODEL` (facultatif, défaut : `gemini-2.5-flash`)

La fonction `/api/config` ne renvoie qu’une URL Supabase HTTPS et une clé publique ; elle refuse les clés `sb_secret_` et les JWT qui ne portent pas le rôle `anon`.

La fonction `/api/chat` utilise un seul fournisseur à la fois, sélectionné côté serveur par `AI_PROVIDER`. OpenAI reste le choix par défaut et conserve ses réglages existants. Pour activer Gemini, ajouter `GEMINI_API_KEY` aux variables Netlify, définir `AI_PROVIDER=gemini`, puis redéployer. La clé Gemini est envoyée à Google dans un en-tête serveur et n’est jamais renvoyée au navigateur. Les deux fournisseurs reçoivent les consignes MadaGrossiste et le catalogue public chargé par la fonction.

Copier `.env.example` vers `.env` pour le développement local avec Netlify CLI. Ne jamais committer `.env`. Ouvrir `index.html` directement avec `file://` permet de voir l’interface, mais les fonctions Supabase et le chat IA nécessitent un serveur Netlify local ou un déploiement Netlify.

## Base Supabase marketplace

Le catalogue, les catégories, les profils, les demandes vendeur, les paniers,
les favoris, les adresses, les messages, les notifications, les commandes, les
zones de livraison, les médias et les promotions sont gérés dans le nouveau
projet Supabase. Aucun produit, vendeur ou commande de démonstration n’est
fourni. Les anciens états locaux ne sont pas importés.

La migration versionnée est `supabase/migrations/20261107000000_marketplace.sql`.
Elle crée le schéma, les relations et index, le profil automatique après
inscription Auth, les RPC sécurisées pour l’administration et les commandes,
les règles RLS, ainsi que le bucket public d’images avec téléversement limité
aux vendeurs approuvés. Les demandes de commande sont enregistrées par vendeur;
le stock est vérifié et réservé dans la même transaction. Aucun paiement en
ligne n’est activé.

Les fiches produits proposent maintenant un mode classique, gros ou mixte, un
prix classique, un prix de gros et jusqu’à 20 paliers de prix par quantité.
Les vendeurs enregistrent les prix, le minimum et les paliers ensemble via un
RPC PostgreSQL transactionnel; les colonnes de prix ne sont pas modifiables
directement depuis le navigateur. Les acheteurs voient le tarif correspondant
à leur quantité dans un tableau de tarifs, avec le palier applicable et un
total estimatif recalculé dans la fiche et le panier. Les contrôles de minimum
et de stock bloquent la poursuite si le panier n’est pas conforme; le RPC de
commande recalcule toujours prix et total à partir des prix stockés dans
PostgreSQL et réserve le stock dans la même transaction. Les estimations de
l’interface ne remplacent pas cette validation serveur.
Le catalogue affiche un état de chargement pendant la lecture Supabase, puis
conserve des états distincts en cas d’erreur, de catalogue vide ou de recherche
sans résultat. Il inclut aussi un guide d’achat et un accès à l’espace vendeur,
sans offres de démonstration ni contacts fictifs.
Les demandes de devis sont privées aux acheteurs et vendeurs concernés. Un
vendeur peut proposer le prix courant, un autre tarif ou refuser; l’acheteur
voit le prix proposé et le total pour la quantité demandée. L’acceptation crée
la commande exclusivement par le RPC de commande, sous réserve du stock encore
disponible. La migration
ajoute les colonnes et tables nécessaires sans supprimer les données ou
commandes existantes; les produits déjà présents gardent le mode gros par
défaut pour préserver leur comportement actuel.

L’espace vendeur récupère ses indicateurs via le RPC PostgreSQL protégé
`mg_seller_dashboard_stats()`, qui calcule les chiffres uniquement pour le
vendeur authentifié (ou l’administrateur). Le chiffre d’affaires inclut les
lignes de commandes confirmées, expédiées ou terminées, et exclut les demandes
en attente et les commandes annulées. Les prix de
commande restent en lecture seule. La table `order_status_history` conserve
les transitions effectuées après la migration et une photographie du statut
courant des commandes préexistantes; les étapes historiques antérieures à la
migration ne peuvent pas être reconstituées.

Le centre administrateur utilise `mg_admin_dashboard_stats()` et les tables
protégées par RLS pour présenter les comptes, les candidatures, les produits,
les commandes et le journal d’activité. La migration additive
`supabase/migrations/20261108000000_admin_control.sql` ajoute la modération
des produits, la suspension/réactivation des vendeurs et un journal en
lecture seule. Les produits existants actifs sont conservés comme approuvés;
les offres inactives deviennent des brouillons, et ne sont donc pas comptées
à tort comme des demandes en attente. Toute modification du contenu ou des
tarifs d’un produit approuvé le désactive et le remet en modération. Un vendeur
peut soumettre son brouillon ou corriger un refus, mais seul un administrateur
peut l’approuver et le publier. La suspension désactive les offres; la
réactivation ne les republie pas automatiquement.

L’indicateur financier administrateur est le volume brut des lignes de
commandes confirmées, expédiées ou terminées. Il ne représente ni une
commission ni un revenu net de la plateforme. Aucune commission ou intégration
de paiement n’est configurée.

### Tests SQL sans Docker

Les tests pgTAP de `supabase/tests/marketplace.test.sql` doivent être exécutés
sur une base PostgreSQL de test locale contenant le schéma Supabase requis.
Ils ne doivent pas être dirigés vers le projet distant. Cette procédure ne
démarre pas Docker, n’applique aucune migration distante et ne réinitialise
aucune base; sans serveur PostgreSQL de test déjà disponible, les tests SQL
restent à exécuter dans un environnement local autorisé.

### Déployer la migration explicitement

Installer Supabase CLI selon la documentation officielle, puis vérifier
attentivement le projet cible avant toute liaison ou migration :

```powershell
supabase login
supabase projects list
$env:SUPABASE_PROJECT_REF = "<référence du nouveau projet vérifiée>"
supabase link --project-ref $env:SUPABASE_PROJECT_REF
Get-Content .\supabase\.temp\project-ref
supabase db push --dry-run
```

Cette procédure est distincte de la validation locale ci-dessus et n’est pas à
exécuter pendant cette préparation. Comparer la référence affichée avec celle du nouveau projet dans le tableau de
bord Supabase et examiner le plan du `--dry-run`. Ne lancer `supabase db push`
qu’après confirmation explicite de la cible. Cette commande n’est pas lancée
par le dépôt. Ne jamais lier l’ancien projet.

### Authentification et administrateur

Les nouveaux comptes sont créés via Supabase Auth et un trigger crée leur
profil. Un compte inscrit comme vendeur reste en attente jusqu’à validation.
Un acheteur déjà inscrit peut envoyer sa demande depuis l’espace vendeur. Les
RPC `mg_apply_as_seller` et `mg_review_seller` contrôlent cette procédure sans
permettre au navigateur de choisir lui-même son rôle.
Pour promouvoir le premier administrateur, créer d’abord son compte dans
l’application, puis exécuter une seule fois dans l’éditeur SQL du nouveau
projet, après avoir vérifié l’UUID du compte :

```sql
update public.profiles
set role = 'admin'
where id = '<UUID du compte vérifié>';
```

Ne pas définir un rôle depuis le navigateur et ne jamais utiliser une clé
`service_role` dans le site. Le navigateur reçoit uniquement la clé publique
du nouveau projet ; les clés d’IA restent des secrets serveur Netlify.

### Modèle de données

Les tables principales sont `categories`, `profiles`, `seller_applications`,
`products`, `carts`, `cart_items`, `buyer_favorites`, `shipping_addresses`,
`orders`, `order_items`, `marketplace_messages`, `marketplace_notifications`,
`seller_delivery_zones`, `product_media` et `marketplace_promotions`.

Les images de produits sont enregistrées dans le bucket `product-images`, sous
un chemin appartenant à l’identifiant du vendeur. Les fonctionnalités
acheteur/vendeur persistantes nécessitent une session Auth. Les permissions
sont imposées par PostgreSQL avec RLS ; la clé publique ne confère pas d’accès
privilégié.

Le numéro professionnel est privé par défaut. Un vendeur approuvé ou en
attente peut choisir dans son espace vendeur de l’afficher publiquement sur
ses offres; ce choix est réversible. Les médias secondaires acceptent pour le
moment des liens externes (image ou vidéo) et ne sont pas téléversés dans
Storage. Les promotions sont consultables dans les outils vendeur, mais leur
création et leur gestion ne sont pas encore disponibles dans l’interface.

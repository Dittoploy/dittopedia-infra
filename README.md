# dittopedia-infra

Infrastructure et orchestration Docker du projet **Dittopedia**.

## Prérequis

- [Docker](https://docs.docker.com/get-docker/) >= 24.0
- [Docker Compose](https://docs.docker.com/compose/) >= 2.20

## Démarrage rapide

```bash
# Copier et adapter les variables d'environnement
cp .env.example .env

# Lancer tous les services (production)
docker compose up -d

# Vérifier que tout tourne
docker compose ps
```

## Mode développement (hot reload)

Le projet utilise deux fichiers Docker Compose :

- **`docker-compose.yml`** : Configuration **production** (target: prod, NODE_ENV=production, sans bind mounts)
- **`docker-compose.dev.yml`** : Override pour **développement local** (target: dev, hot reload, polling)

### Démarrer en développement

```bash
# Arrêt non destructif recommandé après bascule prod <-> dev
docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Optionnel: reset ciblé des seuls volumes node_modules dev
# (adapte le préfixe de projet si différent de "dittopedia-infra")
docker volume rm \
    dittopedia-infra_back_node_modules_dev \
    dittopedia-infra_front_node_modules_dev \
    dittopedia-infra_docs_node_modules_dev

# Lancer avec les overrides de développement
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# Ou utiliser un alias (ajout recommandé dans .bashrc / .zshrc):
# alias docker-dev='docker compose -f docker-compose.yml -f docker-compose.dev.yml'
# docker-dev up --build
```

Le code source local est monté dans les containers (`../dittopedia-back:/app`, etc.) et les dépendances
sont conservées dans des volumes Docker dédiés au dev (`back_node_modules_dev`, `front_node_modules_dev`, `docs_node_modules_dev`).

## Services

### Application

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| `back` | `dittopedia-back` | `3000` | API NestJS |
| `front` | `dittopedia-front` | `3001` | Application Next.js |
| `docs` | `dittopedia-docs` | `3002` | Documentation Nextra |

### Data

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| `postgres` | `dittopedia-postgres` | `5432` | Base de données PostgreSQL 17 |
| `valkey` | `dittopedia-valkey` | `6379` | Cache et sessions (Valkey 8, compatible Redis) |

### Outils

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| `adminer` | `dittopedia-adminer` | `8080` | Interface web d'administration BDD |
| `sonarqube` | `dittopedia-sonarqube` | `9000` | Analyse statique du code |

## URLs locales

| Service | URL |
|---------|-----|
| Backend API | http://localhost:3000 |
| Frontend | http://localhost:3001 |
| Documentation | http://localhost:3002 |
| Adminer | http://localhost:8080 |
| SonarQube | http://localhost:9000 |

## Variables d'environnement

Les variables sont définies dans le fichier `.env` (copier `.env.example`).

| Variable | Défaut | Description |
|----------|--------|-------------|
| `NODE_ENV` | `production` | Environnement Node.js |
| `BACK_PORT` | `3000` | Port exposé pour le backend |
| `FRONT_PORT` | `3001` | Port exposé pour le frontend |
| `DOCS_PORT` | `3002` | Port exposé pour la documentation |
| `POSTGRES_PORT` | `5432` | Port exposé pour PostgreSQL |
| `VALKEY_PORT` | `6379` | Port exposé pour Valkey |
| `ADMINER_PORT` | `8080` | Port exposé pour Adminer |
| `SONARQUBE_PORT` | `9000` | Port exposé pour SonarQube |
| `NEXT_PUBLIC_API_URL` | `http://localhost:3000` | URL publique de l'API |
| `POSTGRES_USER` | `dittopedia` | Utilisateur PostgreSQL |
| `POSTGRES_PASSWORD` | `dittopedia` | Mot de passe PostgreSQL |
| `POSTGRES_DB` | `dittopedia` | Nom de la base de données |
| `SONARQUBE_DB_PASSWORD` | `sonarqube` | Mot de passe de la DB SonarQube |

## Volumes persistants

| Volume | Service | Chemin dans le container |
|--------|---------|--------------------------|
| `postgres_data` | `postgres` | `/var/lib/postgresql/data` |
| `valkey_data` | `valkey` | `/data` |
| `sonarqube_data` | `sonarqube` | `/opt/sonarqube/data` |
| `sonarqube_extensions` | `sonarqube` | `/opt/sonarqube/extensions` |
| `sonarqube_logs` | `sonarqube` | `/opt/sonarqube/logs` |

## Dépendances entre services

```
front ──▶ back ──▶ postgres
               ──▶ valkey
adminer ──▶ postgres
sonarqube ──▶ postgres
docs (indépendant)
```

Le backend attend que **postgres** et **valkey** soient healthy avant de démarrer.

## Notes

- **SonarQube** : identifiants par défaut au premier lancement `admin` / `admin` (changement obligatoire).
- **Adminer** : pré-configuré pour pointer sur le serveur `postgres`. Login avec `POSTGRES_USER` / `POSTGRES_PASSWORD`.
- **init-db.sh** : script exécuté au premier démarrage de PostgreSQL pour créer la base `sonarqube` et son utilisateur dédié.
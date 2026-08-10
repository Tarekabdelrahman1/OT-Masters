# FitGear — Home Gym Equipment Store

A full-stack e-commerce app for home/garage gym gear. Built as the application layer
for a DevSecOps CI/CD pipeline (Docker → Trivy → GKE via ArgoCD).

**Design direction:** "Iron & Chalk" — industrial gym aesthetic (iron black, concrete
grey, hazard orange), condensed display type, mono spec-sheet labels, and a
barbell-loading signature animation in the hero.

## Stack

- **Frontend:** React 18 + Vite, React Router, Axios, plain CSS (design tokens, no framework)
- **Backend:** Node.js + Express, PostgreSQL (`pg`), JWT auth, bcrypt password hashing
- **Infra-ready:** Dockerfiles for both services, `docker-compose.yml` for local dev,
  `/health` endpoint on the API for k8s liveness/readiness probes

## Project layout

```
fitgear/
├── backend/           # Express API
│   ├── src/
│   │   ├── controllers/
│   │   ├── routes/
│   │   ├── middleware/
│   │   ├── db/         # schema.sql + seed.js
│   │   ├── db.js
│   │   └── index.js
│   ├── Dockerfile
│   └── package.json
├── frontend/           # React app
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   ├── context/     # cart + auth state
│   │   ├── api/
│   │   └── styles/       # design tokens + global.css
│   ├── Dockerfile
│   ├── nginx.conf
│   └── package.json
└── docker-compose.yml
```

## Local development

### 1. Database + backend

```bash
cd backend
cp .env.example .env
# edit .env with your local Postgres credentials

npm install
# create the database and tables (run schema.sql against your Postgres instance)
psql -U <user> -d <db> -f src/db/schema.sql

npm run seed     # loads categories + starter products
npm run dev       # starts on http://localhost:4000
```

### 2. Frontend

```bash
cd frontend
cp .env.example .env
npm install
npm run dev        # starts on http://localhost:5173
```

### 3. Or run everything with Docker Compose

```bash
docker compose up --build
```

- Frontend: http://localhost:8080
- Backend API: http://localhost:4000/api
- Postgres: localhost:5432

## API overview

| Method | Route                  | Auth | Description                  |
|--------|-------------------------|------|-------------------------------|
| POST   | `/api/auth/register`    | —    | Create an account             |
| POST   | `/api/auth/login`       | —    | Sign in, returns JWT          |
| GET    | `/api/products`         | —    | List products (`?category=`) |
| GET    | `/api/products/:slug`   | —    | Get one product               |
| GET    | `/api/products/categories` | — | List categories             |
| POST   | `/api/orders`           | JWT  | Place an order (checkout)     |
| GET    | `/api/orders/mine`      | JWT  | List the signed-in user's orders |
| GET    | `/health`               | —    | Liveness/readiness probe      |

## Next steps (for the DevSecOps pipeline)

- These two Dockerfiles are what Jenkins will build, scan with Trivy, and push to ECR.
- `/health` on the backend is ready to wire into k8s liveness/readiness probes.
- Secrets (DB password, JWT secret) should come from Vault at deploy time — never bake
  them into the image or commit `.env`.

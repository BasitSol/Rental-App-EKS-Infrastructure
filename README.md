# RentalApp

RentalApp is a full-stack bike rental platform with a React frontend, an Express backend, and MongoDB for persistence. The repository is organized as a small monorepo with separate app folders plus deployment and infrastructure code.

## What’s inside

- `client-staging/` contains the React frontend.
- `api-staging/` contains the Node.js and Express backend.
- `k8s/` contains Kustomize manifests for local and production deployments.
- `terraform/` contains AWS-oriented infrastructure code.

## Clone and set up

```bash
git clone https://github.com/BasitSol/RentalApp-DevOps.git
cd RentalApp
```

Install the app dependencies:

```bash
cd api-staging && npm install
cd ../client-staging && npm install
```

## Environment files

Copy the example files before running anything locally:

```bash
cp .env.example .env
cp api-staging/.env.example api-staging/.env
```

Use your own MongoDB connection and secrets in the copied files. Never commit real secrets.

## Local development

### Backend

```bash
cd api-staging
npm run dev
```

### Frontend

```bash
cd client-staging
npm start
```

## Recommended local workflow

If you want the easiest local setup, follow this order:

1. Clone the repo.
2. Copy the example environment files.
3. Install backend and frontend dependencies.
4. Start the backend.
5. Start the frontend.
6. Confirm the app works before pushing changes.

## Docker Compose

The repository includes a root-level Docker Compose setup for running the app with env-driven configuration.

```bash
cp .env.example .env
docker compose up --build
```

Set `MONGODB_URI`, `SESSION_SECRET`, and `CLIENT_URL` in `.env` before starting the stack. For the live EKS deployment, `CLIENT_URL` should point at the ELB hostname (`http://ae3b0296de3e84446aba612ab8ecb1ea-817453542.us-east-1.elb.amazonaws.com`). The frontend build reads `REACT_APP_API_URL` at build time.

## Available scripts

### Backend (`api-staging`)

- `npm start` - start the API.
- `npm run dev` - start the API with nodemon.

### Frontend (`client-staging`)

- `npm start` - start the React development server.
- `npm run build` - create a production build.
- `npm test` - run the React test suite.
- `npm run deploy:prod` - run the frontend deployment script.

## Deployment

### Kubernetes

The Kubernetes setup is split into a reusable base and environment-specific overlays.

- Production-oriented workflow: [k8s/README.md](k8s/README.md)
- Post-deploy checks: [k8s/verification-runbook.md](k8s/verification-runbook.md)

### Frontend static deploy

The frontend deployment script uploads the production build to S3 and refreshes CloudFront:

```bash
cd client-staging
FRONTEND_BUCKET_NAME=your-bucket-name \
CLOUDFRONT_DISTRIBUTION_ID=your-distribution-id \
AWS_REGION=us-east-1 \
npm run deploy:prod
```

## Notes

- The backend uses session-based authentication with Passport.
- The frontend expects the API to be reachable from the same deployment environment or through the configured API base URL.
- Keep generated files, Terraform state, and secrets out of Git.

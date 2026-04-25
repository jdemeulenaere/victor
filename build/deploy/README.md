# Deploy Setup

This document walks through creating the Google Cloud and Firebase resources required by the Bazel deploy targets and GitHub Actions workflow in this repository.

Use one Google Cloud / Firebase project per environment.

Recommended environment layout:
- `victor-dev`
- `victor-staging`
- `victor-prod`

For the current dev setup, create these resources:
- GCP project: `victor-dev`
- Region: `europe-west1`
- Artifact Registry repository: `victor-dev`
- Cloud Run service: `greeter-backend-dev`
- Firebase Hosting site: `greeter-web-dev`
- Firebase Android app package: `victor.greeter.android`
- App Distribution group: `android-dev-testers`
- GitHub deploy service account: `victor-deployer@victor-dev.iam.gserviceaccount.com`

## 1. Create the Google Cloud project

Create a Google Cloud project and attach billing.

After creation, set your local CLI context:

```bash
gcloud config set project victor-dev
PROJECT_ID=victor-dev
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
echo "$PROJECT_ID"
echo "$PROJECT_NUMBER"
```

## 2. Enable required GCP APIs

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  serviceusage.googleapis.com
```

## 3. Add Firebase to the existing GCP project

In the Firebase console:
- Create a project
- Choose `Add Firebase to existing Google Cloud project`
- Select your GCP project, for example `victor-dev`
- Analytics is optional for this setup

## 4. Create the Firebase Hosting site

Install the Firebase CLI if needed:

```bash
npm install -g firebase-tools
```

Then authenticate and create the site directly against the target project:

```bash
firebase login
firebase projects:list
firebase hosting:sites:create greeter-web-dev --project victor-dev
```

Verify it:

```bash
firebase hosting:sites:list --project victor-dev
```

Do not use `firebase use` for this setup unless you are inside a Firebase project directory.

## 5. Register the Android app in Firebase

In the Firebase console:
- Open the target Firebase project
- Add an Android app
- Android package name: `victor.greeter.android`
- App nickname: `Victor Android Dev`

Copy the Firebase App ID after registration. It looks like this:

```text
1:1234567890:android:abcdef123456
```

That value is required by `deploy_android_app(...)` in `src/samples/greeter/android/BUILD.bazel`.

## 6. Create the App Distribution tester group

```bash
firebase appdistribution:group:create "Android Dev Testers" android-dev-testers --project victor-dev
```

## 7. Create the Artifact Registry repository

```bash
gcloud artifacts repositories create victor-dev \
  --repository-format=docker \
  --location=europe-west1 \
  --description="Victor dev images"
```

## 8. Create the GitHub deploy service account and grant roles

Create the service account:

```bash
gcloud iam service-accounts create victor-deployer \
  --display-name="Victor GitHub deployer"
```

For least privilege, treat this as two separate actors:
- a human bootstrap admin, used once to create the infrastructure
- the GitHub CI deployer service account, used only to deploy to already-created resources

### 8a. One-time bootstrap by a human admin

The human bootstrap admin creates the project resources in steps 1 through 7 and configures Workload Identity in step 9.

For Cloud Run, the narrow steady-state CI role works best once the target service already exists. You have two bootstrap options:
- create the initial Cloud Run service once using your human account
- or temporarily grant the CI deployer `roles/run.admin` at the project level for the first deploy only, then remove it after the service exists

The recommended path is to create the initial service once as a human and keep the CI service account narrow.

Create the initial `greeter-backend-dev` service once using a public sample container:

```bash
gcloud run deploy greeter-backend-dev \
  --image us-docker.pkg.dev/cloudrun/container/hello \
  --project="$PROJECT_ID" \
  --region=europe-west1 \
  --platform=managed \
  --allow-unauthenticated
```

Verify that the service exists:

```bash
gcloud run services describe greeter-backend-dev \
  --project="$PROJECT_ID" \
  --region=europe-west1 \
  --format='value(status.url)'
```

This placeholder service is only there to establish the Cloud Run service resource. After the repository config is populated with real values, the human bootstrap admin or the CI workflow can replace it with the actual Kotlin backend image by running the normal deploy flow.

### 8b. Steady-state CI deployer roles

Grant only the project-level roles that must remain project-scoped:

```bash
DEPLOYER="victor-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${DEPLOYER}" \
  --role="roles/firebasehosting.admin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${DEPLOYER}" \
  --role="roles/firebaseappdistro.admin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${DEPLOYER}" \
  --role="roles/serviceusage.apiKeysViewer"
```

Grant Artifact Registry write access only on the specific repository:

```bash
gcloud artifacts repositories add-iam-policy-binding victor-dev \
  --location=europe-west1 \
  --member="serviceAccount:${DEPLOYER}" \
  --role="roles/artifactregistry.writer"
```

Grant Cloud Run deploy access only on the specific service:

```bash
gcloud run services add-iam-policy-binding greeter-backend-dev \
  --region=europe-west1 \
  --member="serviceAccount:${DEPLOYER}" \
  --role="roles/run.developer"
```

Allow that deployer service account to act as the runtime service account used by Cloud Run. The current repository uses the default Compute Engine runtime service account:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --member="serviceAccount:${DEPLOYER}" \
  --role="roles/iam.serviceAccountUser"
```

If you used a temporary bootstrap grant for the first deploy, remove it afterward:

```bash
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${DEPLOYER}" \
  --role="roles/run.admin"
```

## 9. Configure GitHub OIDC / Workload Identity Federation

Set your GitHub repository first:

```bash
GITHUB_REPO="OWNER/REPO"
```

Create the workload identity pool and provider:

```bash
gcloud iam workload-identity-pools create github \
  --location=global \
  --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers create-oidc victor \
  --location=global \
  --workload-identity-pool=github \
  --display-name="Victor GitHub provider" \
  --issuer-uri="https://token.actions.githubusercontent.com/" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='${GITHUB_REPO}' && assertion.ref=='refs/heads/main'"

gcloud iam service-accounts add-iam-policy-binding "${DEPLOYER}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/${GITHUB_REPO}"
```

The workflow field `github_actions.workload_identity_provider` should end up looking like this:

```text
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/victor
```

## 9a. Verify the CI deployer permissions

Run the checked-in verifier:

```bash
PROJECT_ID="victor-dev-493319" \
REGION="europe-west1" \
REPOSITORY="victor-dev" \
SERVICE="greeter-backend-dev" \
./build/deploy/verify_ci_permissions.sh
```

Or via Bazel:

```bash
bazel run //build/deploy:verify_ci_permissions
```

The verifier checks:
- project-level roles
- Artifact Registry repository-level role
- Cloud Run service-level role
- runtime service account impersonation role

## 10. Update the repository with the real values

Populate these values in `build/deploy/dev_environment.json`:
- `gcp.project_id`
- `gcp.region`
- `gcp.artifact_registry_repository`
- `github_actions.workload_identity_provider`
- `github_actions.service_account`
- `firebase.project_id`
- `firebase.default_tester_groups`

Replace the placeholder Firebase App ID in `src/samples/greeter/android/BUILD.bazel`.

After updating those values, validate the setup locally:

```bash
bazel run //src/samples/greeter/backend:deploy -- --dry-run
bazel run //src/samples/greeter/web:deploy -- --dry-run
bazel run //src/samples/greeter/android:deploy -- --dry-run
```

Then validate the repo-wide build and test contract:

```bash
./build.sh
./test.sh
```

# GitHub Actions Workflows Folder

This folder owns the CI/CD pipeline configuration files that automate the compiling, tagging, testing, and deployment of the FastAPI application. It connects code updates in Git to the ECR registry and updates the Helm values dynamically.

## Architecture

```
+-------------------------------------------------------------+
|                     workflows/ Folder                       |
|                                                             |
|  +-------------------------------------------------------+  |
|  |                     app-ci.yaml                       |  |
|  |                                                       |  |
|  |  [Checkout] -> [Auth AWS] -> [ECR Login] -> [Build]   |  |
|  |  -> [Push Image] -> [Update Helm] -> [Git Push]        |  |
|  |  +-------------------------------------------------------+  |
+-------------------------------------------------------------+
```

| Component | Upstream Input | Downstream Output |
|:---|:---|:---|
| `app-ci.yaml` | `app/` changes | `k8s/fastapi/values.yaml` |

## File-by-file explanation

### app-ci.yaml

The workflow defined in `app-ci.yaml` builds and deploys the FastAPI container image automatically.

Here is the annotated version of `app-ci.yaml` showing detailed field-level comments:

```yaml
# The name defines the workflow title in the GitHub Actions UI.
name: Build and Deploy FastAPI

# Specifies the trigger events for this automation workflow.
on:
  # Allows triggering this workflow manually via GitHub Web UI or CLI.
  workflow_dispatch:
  # Triggers the workflow automatically when code is pushed to Git.
  push:
    # Restricts the push trigger only to changes on the main branch.
    branches: [main]
    # Scopes execution to source files under app or fastapi helm configuration.
    # If these filters are incorrect, pushes to documentation or Terraform
    # files will trigger unnecessary ECR builds and image push steps.
    paths:
      - "app/**"
      - "k8s/fastapi/**"

# Global environment variables shared across all jobs in this workflow.
env:
  # Target AWS Region for ECR where EKS and Karpenter pull the image.
  # Must match variable aws_region in terraform/variables.tf.
  AWS_REGION: ap-south-1
  # The ECR repository name created by the Terraform ECR module.
  # Must match ecr_repository in terraform/ecr.tf.
  ECR_REPOSITORY: fastapi-app
  # Injects the AWS account ID from GitHub secrets to build the registry URL.
  AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID }}

# Group of execution jobs to build, package, and deploy the application.
jobs:
  # Unique job ID for building and pushing the container.
  build-and-push:
    # Human-readable name displayed in GitHub workflow run logs.
    name: Build → Push → Update Manifest
    # Specifies the runner operating system type.
    runs-on: ubuntu-latest
    # Configures permissions for the GITHUB_TOKEN within this job context.
    permissions:
      # Grants write access to contents so git push can update values.yaml.
      # If missing, git push fails with authentication error.
      contents: write

    # The sequential list of build steps to perform.
    steps:
      # Step to check out the repository code into the runner's workspace.
      - name: Checkout code
        uses: actions/checkout@v4

      # Step to authenticate with AWS APIs using static IAM credentials.
      # Must match credentials configured in GitHub Secrets.
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      # Step to log in to the private ECR registry for Docker image push.
      - name: Log in to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      # Step to generate a short image tag using the Git commit SHA.
      # Sets steps.meta.outputs.tag to the first 8 characters.
      - name: Set image tag
        id: meta
        run: echo "tag=${GITHUB_SHA::8}" >> "$GITHUB_OUTPUT"

      # Step to build and push the Docker image to AWS ECR.
      # Injects ECR registry URL and generated image tag.
      - name: Build, tag, and push image
        env:
          REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ steps.meta.outputs.tag }}
        run: |
          docker build -t "$REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" ./app
          docker push "$REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
          echo "Image: $REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

      # Step to update k8s/fastapi/values.yaml repository and tag keys using sed.
      # Ensures that ArgoCD detects the change and triggers a deployment.
      - name: Update deployment image tag
        env:
          REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ steps.meta.outputs.tag }}
        run: |
          sed -i "s|repository: .*|repository: \"$REGISTRY/$ECR_REPOSITORY\"|g" k8s/fastapi/values.yaml
          sed -i "s|tag: .*|tag: \"$IMAGE_TAG\"|g" k8s/fastapi/values.yaml

      # Step to commit and push the updated Helm values.yaml manifest to Git.
      # Uses [skip ci] to prevent a recursive GitHub Actions workflow trigger loop.
      - name: Commit updated manifest
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s/fastapi/values.yaml
          git commit -m "ci: update fastapi image to ${GITHUB_SHA::8} [skip ci]"
          git push
```

## Versions and APIs used

| Action Name | Version | Purpose |
|:---|:---|:---|
| `actions/checkout` | `v4` | Clone source code |
| `aws-actions/configure-aws-credentials` | `v4` | AWS authentication |
| `aws-actions/amazon-ecr-login` | `v2` | ECR registry authentication |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| AWS IAM user | User with ECR push permissions | AWS Console |
| GitHub Secrets | `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` configured | GitHub Settings |
| GitHub Secrets | `AWS_ACCOUNT_ID` configured | GitHub Settings |

## Commands

We trigger the build pipeline by pushing a change to the FastAPI application code.
```bash
git add app/
git commit -m "feat: update FastAPI codebase"
git push origin main
```

We trigger the build pipeline manually from the GitHub actions interface by using the workflow dispatch parameters.
```bash
gh workflow run "Build and Deploy FastAPI" --branch main
```

## Troubleshooting

We resolve AWS login failures by verifying that the repository secrets contain valid IAM credentials with active keys in the AWS Console.

We resolve git push failures by verifying that the GitHub Actions settings allow Read/Write permissions and checking that branch protection rules do not block direct pushes to `main`.

We resolve ECR upload failures by verifying that the ECR repository name in `app-ci.yaml` matches the registry created by the Terraform scripts.

## References

| Tool | Official Documentation |
|:---|:---|
| GitHub Actions | [Actions Reference](https://docs.github.com/en/actions) |
| Amazon ECR Action | [Amazon ECR Login Action](https://github.com/aws-actions/amazon-ecr-login) |
| Configure AWS credentials | [Configure AWS credentials Action](https://github.com/aws-actions/configure-aws-credentials) |

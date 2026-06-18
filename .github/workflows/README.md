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
|  +-------------------------------------------------------+  |
+-------------------------------------------------------------+
```

| Component | Upstream Input | Downstream Output |
|:---|:---|:---|
| `app-ci.yaml` | `app/` changes | `k8s/fastapi/values.yaml` |

## File-by-file explanation

### app-ci.yaml

The `name: Build and Deploy FastAPI` field defines the display name of this workflow in the GitHub Actions UI.

The `on` block declares the execution trigger events for the workflow.
The `workflow_dispatch` field enables manual execution of the pipeline via the GitHub web UI.
The `push` trigger starts the workflow on git pushes.
The `branches` filter scopes this push trigger specifically to the `main` branch.
The `paths` block limits execution to occurrences where changes are made inside `app/**` or `k8s/fastapi/**`. If wrong or missing, the pipeline will trigger on every commit, including documentation or Terraform changes, leading to unnecessary ECR builds.

The `env` block defines environment variables shared across all jobs in the workflow.
The `AWS_REGION: ap-south-1` field sets the target AWS region for the container registry, which must align with the `aws_region` parameter in [variables.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/variables.tf#L18).
The `ECR_REPOSITORY: fastapi-app` field specifies the target ECR registry repository name. It must align with the `name` property inside [ecr.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/ecr.tf#L31). If mismatched, image pushes will be rejected with resource not found errors.
The `AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID }}` field references the secret holding your AWS account ID.

The `jobs` section contains the orchestration jobs to be run.
The `build-and-push` job defines the packaging sequence.
The `runs-on: ubuntu-latest` configuration directs GitHub to allocate an ephemeral Ubuntu runner virtual machine.
The `permissions` block configures the security permissions granted to the runner's GitHub token.
The `contents: write` permission is required to allow the workflow runner to commit updated manifests back to the Git repository. Without this permission, the git push step fails.

The `steps` list declares the sequential build actions.
The `uses: actions/checkout@v4` step clones the codebase onto the runner virtual machine.
The `uses: aws-actions/configure-aws-credentials@v4` step sets up access parameters for the AWS CLI and SDK calls.
The `aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}` parameter injects the AWS Access Key ID secret.
The `aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}` parameter injects the AWS Secret Access Key secret.
The `aws-region: ${{ env.AWS_REGION }}` parameter configures the target region. If these secrets are invalid or missing, authentication checks with AWS will fail.
The `uses: aws-actions/amazon-ecr-login@v2` step logs the local Docker daemon into the private ECR registry.
The `run: echo "tag=${GITHUB_SHA::8}" >> "$GITHUB_OUTPUT"` step generates a unique 8-character image tag from the git commit SHA.
The `docker build` and `docker push` commands compile the Docker image using the [Dockerfile](file:///home/selva/Documents/k8s/karpenter_simple_example/app/Dockerfile) and upload it to the ECR registry.
The `sed -i` commands update the image repository and tag parameters inside [values.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/fastapi/values.yaml). If wrong, ArgoCD will continue deploying the old container version.
The `git commit -m "... [skip ci]"` command commits the manifest changes. The `[skip ci]` string is critical; omitting it causes the workflow to trigger another run on the bot's commit, creating an infinite build loop.
The `git push` command pushes the updated files to GitHub.

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

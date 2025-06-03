<div align="center">

# Customizable Self-hosted GitHub Runners

Leveraging the power of [terraform-aws-github-runner](https://github.com/philips-labs/terraform-aws-github-runner), this project introduces an innovative way to manage self-hosted GitHub runners.

</div>

## Table of Runner Types

We provide a variety of self-hosted runner configurations. Choose the one that best suits your project's needs (each runner is labelled with `size`, `OS` and `architecture`):

| Size | OS | Architecture | Instance Type |
| --- | --- | --- | --- |
| 5xlarge | Ubuntu Noble 24.04 | x64 | [c5.4xlarge](https://instances.vantage.sh/?selected=c5.4xlarge) |
| 4xlarge | Ubuntu Noble 24.04 | x64 | [c5.4xlarge](https://instances.vantage.sh/?selected=c5.4xlarge) |
| 2xlarge | Ubuntu Noble 24.04 | x64 | [c5.2xlarge](https://instances.vantage.sh/?selected=c5.2xlarge) |
| xlarge | Ubuntu Noble 24.04 | x64 | [c5.xlarge](https://instances.vantage.sh/?selected=c5.xlarge) or [m5.xlarge](https://instances.vantage.sh/?selected=m5.xlarge) |
| large | Ubuntu Noble 24.04 | x64 | [c5.large](https://instances.vantage.sh/?selected=c5.large) or [m5.large](https://instances.vantage.sh/?selected=m5.large) |
| 4xlarge | Ubuntu Noble 24.04 | arm64 | [m7g.4xlarge](https://instances.vantage.sh/?selected=m7g.4xlarge) |
| 2xlarge | Ubuntu Noble 24.04 | arm64 | [m7g.2xlarge](https://instances.vantage.sh/?selected=m7g.4xlarge) |
| xlarge | Ubuntu Noble 24.04 | arm64 | [m7g.xlarge](https://instances.vantage.sh/?selected=m7g.xlarge) |
| 2xlarge (with GPU) | Ubuntu Noble 24.04 | x64 | [g4dn.2xlarge](https://instances.vantage.sh/?selected=g4dn.2xlarge) |
| xlarge (with GPU) | Ubuntu Noble 24.04 | x64 | [g4dn.xlarge](https://instances.vantage.sh/?selected=g4dn.xlarge) |
| 2xlarge | Windows Server 2022 | x64 | [c5.2xlarge](https://instances.vantage.sh/?selected=c5.2xlarge) |
| xlarge | Windows Server 2022 | x64 | [c5.xlarge](https://instances.vantage.sh/?selected=c5.xlarge) or [m5.xlarge](https://instances.vantage.sh/?selected=m5.xlarge) |

## Getting Started

### Using an Existing Self-hosted Runner Type

Specify the self-hosted runner in your workflow by setting the `job.runs-on` parameter. For instance, `runs-on: [self-hosted, linux, x64, 4xlarge]`, `runs-on: [self-hosted, windows, x64, xlarge]`.

#### Concerned about Security?

If you're wondering about the security implications of using self-hosted runners in public repositories, consider these pointers:

- We suggest familiarizing yourself with GitHub's official guidelines on [security implications of using self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners#self-hosted-runner-security).
- To combat the risk of retaining unwanted or dangerous data, our project only supports ephemeral runners, which are discarded after running a single workflow.
- For an extra layer of protection against untrusted code execution, you might consider these strategies:
  - [Require approval for workflow execution from all outside collaborators](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#controlling-changes-from-forks-to-workflows-in-public-repositories), providing you with an opportunity to review the code before execution.
  - [Restrict workflows that can use self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-access-to-self-hosted-runners-using-groups#changing-the-access-policy-of-a-self-hosted-runner-group). This will prevent the use of self-hosted runners for workflows triggered on [pull_request](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request) as it requires providing the exact git ref.

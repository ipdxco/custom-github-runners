#!/bin/bash -e
exec > >(tee /var/log/runner-startup.log | logger -t user-data -s 2>/dev/console) 2>&1

cd /opt/actions-runner

# shellcheck shell=bash

## Retrieve instance metadata

echo "Retrieving TOKEN from AWS API"
token=$(curl -f -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 180")

region=$(curl -f -H "X-aws-ec2-metadata-token: $token" -v http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
echo "Retrieved REGION from AWS API ($region)"

instance_id=$(curl -f -H "X-aws-ec2-metadata-token: $token" -v http://169.254.169.254/latest/meta-data/instance-id)
echo "Retrieved INSTANCE_ID from AWS API ($instance_id)"

tags=$(aws ec2 describe-tags --region "$region" --filters "Name=resource-id,Values=$instance_id")
echo "Retrieved tags from AWS API ($tags)"

environment=$(echo "$tags" | jq -r '.Tags[]  | select(.Key == "ghr:environment") | .Value')
echo "Retrieved ghr:environment tag - ($environment)"

parameters=$(aws ssm get-parameters-by-path --path "/$environment/runner" --region "$region" --query "Parameters[*].{Name:Name,Value:Value}")
echo "Retrieved parameters from AWS SSM ($parameters)"

run_as=$(echo "$parameters" | jq --arg environment "$environment" -r '.[] | select(.Name == "/\($environment)/runner/run-as") | .Value')
echo "Retrieved /$environment/runner/run-as parameter - ($run_as)"

enable_cloudwatch_agent=$(echo "$parameters" | jq --arg environment "$environment" -r '.[] | select(.Name == "/\($environment)/runner/enable-cloudwatch") | .Value')
echo "Retrieved /$environment/runner/enable-cloudwatch parameter - ($enable_cloudwatch_agent)"

agent_mode=$(echo "$parameters" | jq --arg environment "$environment" -r '.[] | select(.Name == "/\($environment)/runner/agent-mode") | .Value')
echo "Retrieved /$environment/runner/agent-mode parameter - ($agent_mode)"

if [[ "$enable_cloudwatch_agent" == "true" ]]; then
  echo "Cloudwatch is enabled"
  amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c "ssm:$environment-cloudwatch_agent_config_runner"
fi

## Configure docker registries

docker_parameters=$(aws ssm get-parameters-by-path --path "/tf-aws-gh-runner/docker" --region "$region" --query "Parameters[*].{Name:Name,Value:Value}")
echo "Retrieved docker parameters from AWS SSM ($parameters)"

docker_proxy=$(echo "$docker_parameters" | jq -r '.[] | select(.Name == "/tf-aws-gh-runner/docker/proxy_aws_lb_dns_name") | .Value')
echo "Retrieved /tf-aws-gh-runner/docker/proxy_aws_lb_dns_name parameter - ($docker_proxy)"

sudo mkdir -p /etc/docker
sudo echo '{' > /etc/docker/daemon.json
sudo echo '  "insecure-registries": [' >> /etc/docker/daemon.json
sudo echo '    "'"$docker_proxy"'"' >> /etc/docker/daemon.json
sudo echo '  ],' >> /etc/docker/daemon.json
sudo echo '  "registry-mirrors": [' >> /etc/docker/daemon.json
sudo echo '    "'"http://$docker_proxy"'"' >> /etc/docker/daemon.json
sudo echo '  ]' >> /etc/docker/daemon.json
sudo echo '}' >> /etc/docker/daemon.json

sudo mkdir -p /etc/buildkit
sudo echo 'insecure-entitlements = [' > /etc/buildkit/buildkitd.toml
sudo echo '  "network.host",' >> /etc/buildkit/buildkitd.toml
sudo echo '  "security.insecure"' >> /etc/buildkit/buildkitd.toml
sudo echo ']' >> /etc/buildkit/buildkitd.toml
sudo echo '[registry."docker.io"]' >> /etc/buildkit/buildkitd.toml
sudo echo '  mirrors = [' >> /etc/buildkit/buildkitd.toml
sudo echo '    "'"$docker_proxy"'"' >> /etc/buildkit/buildkitd.toml
sudo echo '  ]' >> /etc/buildkit/buildkitd.toml
sudo echo '[registry."'"$docker_proxy"'"]' >> /etc/buildkit/buildkitd.toml
sudo echo '  http = true' >> /etc/buildkit/buildkitd.toml
sudo echo '  insecure = true' >> /etc/buildkit/buildkitd.toml

sudo service docker restart
docker buildx create --driver=docker-container --driver-opt=image=moby/buildkit@sha256:8a45f8c8fcfb0f38e7380d7d9fc728219d2fdf43fd02aee60a2a6723d89abdea --config=/etc/buildkit/buildkitd.toml --name=buildkit

## Configure the runner

echo "Get GH Runner config from AWS SSM"
config=$(aws ssm get-parameters --names "$environment"-"$instance_id" --with-decryption --region "$region" | jq -r ".Parameters | .[0] | .Value")

while [[ -z "$config" ]]; do
  echo "Waiting for GH Runner config to become available in AWS SSM"
  sleep 1
  config=$(aws ssm get-parameters --names "$environment"-"$instance_id" --with-decryption --region "$region" | jq -r ".Parameters | .[0] | .Value")
done

echo "Delete GH Runner token from AWS SSM"
aws ssm delete-parameter --name "$environment"-"$instance_id" --region "$region"

if [ -z "$run_as" ]; then
  echo "No user specified, using default ec2-user account"
  run_as="ec2-user"
fi

if [[ "$run_as" == "root" ]]; then
  echo "run_as is set to root - export RUNNER_ALLOW_RUNASROOT=1"
  export RUNNER_ALLOW_RUNASROOT=1
fi

chown -R $run_as .

echo "Configure GH Runner as user $run_as"
sudo --preserve-env=RUNNER_ALLOW_RUNASROOT -u "$run_as" -- ./config.sh --unattended --name "$instance_id" --work "_work" $${config}

## Start the runner
echo "Starting runner after $(awk '{print int($1/3600)":"int(($1%3600)/60)":"int($1%60)}' /proc/uptime)"
echo "Starting the runner as user $run_as"

if [[ $agent_mode = "ephemeral" ]]; then
  echo "Starting the runner in ephemeral mode"
  sudo --preserve-env=RUNNER_ALLOW_RUNASROOT -u "$run_as" -- ./run.sh
  echo "Runner has finished"

  echo "Stopping cloudwatch service"
  systemctl stop amazon-cloudwatch-agent.service
  echo "Terminating instance"
  aws ec2 terminate-instances --instance-ids "$instance_id" --region "$region"
else
  echo "Installing the runner as a service"
  ./svc.sh install "$run_as"
  echo "Starting the runner in persistent mode"
  ./svc.sh start
fi

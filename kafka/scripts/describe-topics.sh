# Kafka — describir tópicos del clúster
# Uso desde la raíz del repo (Git Bash / WSL) o en la EC2:
#   bash kafka/scripts/describe-topics.sh

set -euo pipefail
cd "$(dirname "$0")/.."

docker compose --env-file .env -f compose.yml exec -T kafka-1 \
  kafka-topics --bootstrap-server localhost:9092 --describe

# Kafka — consumer groups
# Uso desde la raíz del repo (Git Bash / WSL) o en la EC2:
#   bash kafka/scripts/consumer-groups.sh            # lista los grupos
#   bash kafka/scripts/consumer-groups.sh --describe # detalle de cada grupo

set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -eq 0 ]; then set -- --list; fi

docker compose --env-file .env -f compose.yml exec -T kafka-1 \
  kafka-consumer-groups --bootstrap-server localhost:9092 "$@"

.DEFAULT_GOAL := help
.PHONY: help build up down restart ps logs logs-master logs-worker1 logs-worker2 \
        submit pyspark spark-shell wordcount clean prune ui

COMPOSE      := docker compose
JOB          ?= /opt/spark-apps/word_count.py
MASTER_URL   := spark://spark-master:7077
EXEC_MEM     ?= 1g
EXEC_CORES   ?= 2

## help: mostra esta ajuda (target padrão)
help:
	@echo "Uso: make <target>"
	@echo ""
	@grep -E '^## [a-zA-Z0-9_-]+:' Makefile | sed 's/## /  /' | column -t -s ':'

## build: builda a imagem customizada do Spark (Dockerfile)
build:
	$(COMPOSE) build

## up: sobe o cluster (master + 2 workers) em background
up:
	$(COMPOSE) up -d

## down: para e remove os containers (mantém os volumes de log)
down:
	$(COMPOSE) down

## restart: reinicia o cluster (down + up)
restart: down up

## ps: lista status dos containers do cluster
ps:
	$(COMPOSE) ps

## logs: segue os logs de todos os serviços
logs:
	$(COMPOSE) logs -f

## logs-master: segue os logs apenas do master
logs-master:
	$(COMPOSE) logs -f spark-master

## logs-worker1: segue os logs apenas do worker 1
logs-worker1:
	$(COMPOSE) logs -f spark-worker-1

## logs-worker2: segue os logs apenas do worker 2
logs-worker2:
	$(COMPOSE) logs -f spark-worker-2

## wordcount: roda o job de validação word_count.py no cluster
wordcount:
	docker exec -it spark-master /opt/spark/bin/spark-submit \
		--master $(MASTER_URL) \
		--executor-memory $(EXEC_MEM) \
		--total-executor-cores $(EXEC_CORES) \
		/opt/spark-apps/word_count.py

## submit: roda um job PySpark arbitrário no cluster. Uso: make submit JOB=/opt/spark-apps/meu_job.py
submit:
	docker exec -it spark-master /opt/spark/bin/spark-submit \
		--master $(MASTER_URL) \
		--executor-memory $(EXEC_MEM) \
		--total-executor-cores $(EXEC_CORES) \
		$(JOB)

## pyspark: abre um shell PySpark interativo conectado ao cluster
pyspark:
	docker exec -it spark-master /opt/spark/bin/pyspark --master $(MASTER_URL)

## spark-shell: abre um shell Scala (spark-shell) interativo conectado ao cluster
spark-shell:
	docker exec -it spark-master /opt/spark/bin/spark-shell --master $(MASTER_URL)

## ui: abre a Web UI do Master no navegador padrão
ui:
	xdg-open http://localhost:8080 >/dev/null 2>&1 &

## clean: para os containers e remove os volumes nomeados (logs)
clean:
	$(COMPOSE) down -v

## prune: clean + remove a imagem construída localmente
prune: clean
	docker image rm spark-standalone:3.5.9 --force

## notebook: sobe (ou builda+sobe) o Jupyter Lab conectado ao cluster
notebook:
	$(COMPOSE) up -d --build spark-notebook

## notebook-url: mostra a URL de acesso do Jupyter Lab (com token)
notebook-url:
	@$(COMPOSE) logs spark-notebook 2>/dev/null | grep -m1 "http://127.0.0.1:8888/lab?token" || \
		echo "Ainda sem log de URL — rode 'make notebook' primeiro ou aguarde alguns segundos."

## notebook-logs: segue os logs do Jupyter Lab
notebook-logs:
	$(COMPOSE) logs -f spark-notebook
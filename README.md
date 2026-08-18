# Apache Spark em Docker — Guia Completo (Arch Linux)

Cluster standalone (1 Master + 2 Workers) usando a imagem **oficial** do Apache Spark
como base, seguindo o padrão documentado em `spark.apache.org/docs/latest/spark-standalone.html`
e no repositório oficial de imagens `github.com/apache/spark-docker`.

Estrutura do projeto:

```
spark-docker/
├── Dockerfile              # imagem de master/worker (produção do cluster)
├── Dockerfile.notebook     # imagem do cliente Jupyter Lab (dev)
├── docker-compose.yml
├── Makefile
├── requirements.txt        # deps Python de runtime (jobs)
├── requirements-dev.txt    # deps só de desenvolvimento (Jupyter)
├── app/
│   └── word_count.py       # job de validação (PySpark)
├── data/
│   └── sample.txt          # dados de exemplo
└── notebooks/
    └── 00_getting_started.ipynb
```

---

## 1. Por que essa imagem base

Recomendação: **imagem oficial `apache/spark`** (mantida pela própria Apache Software
Foundation), em vez de construir do zero sobre `ubuntu:latest`/`debian:slim`.

| Critério                                                  | `apache/spark` (oficial)                 | Ubuntu/Debian "cru"                        |
| ---------------------------------------------------------- | ------------------------------------------ | ------------------------------------------ |
| JDK correto pré-instalado e testado                       | Sim                                        | Você instala e valida manualmente         |
| Download/checksum/assinatura GPG do Spark                  | Já feito pelo pipeline oficial de release | Você precisa baixar e verificar           |
| Usuário não-root configurado                             | Sim (`spark`)                            | Você precisa configurar                   |
| Testado em CI pela comunidade Spark (build/standalone/k8s) | Sim                                        | N/A                                        |
| Reprodutibilidade de versão (Spark+Scala+Java+SO na tag)  | Sim, explícito na tag                     | Depende de como você escreve o Dockerfile |

A tag usada aqui (`3.5.9-scala2.12-java17-python3-ubuntu`) já é baseada em Ubuntu —
ou seja, você ganha a base Ubuntu que pediu **e** todo o trabalho de empacotamento
do Spark já validado pela Apache, ao invés de refazer esse trabalho manualmente.
Isso é o que a documentação oficial recomenda: usar as imagens publicadas em
`hub.docker.com/r/apache/spark` ou `_/spark` (Docker Official Image).

> Nota sobre versão: no momento em que este guia foi gerado, `3.5.9` é a série
> **LTS** mais recente da linha 3.5.x e `4.2.0` é a última major (Scala 2.13).
> Se seu projeto puder migrar para Spark 4.x, troque `SPARK_VERSION`/`SCALA_VERSION`
> no topo do `Dockerfile` — o restante do guia não muda.

---

## 2. Pré-requisitos no Arch Linux

```bash
# Docker e Docker Compose plugin
sudo pacman -S docker docker-compose

# Habilitar e iniciar o serviço
sudo systemctl enable --now docker.service

# (opcional, recomendado) usar docker sem sudo
sudo usermod -aG docker $USER
newgrp docker

# Validar instalação
docker --version
docker compose version
```

---

## 3. Build da imagem customizada

Dentro da pasta `spark-docker/`:

```bash
docker compose build
```

Isso vai:

1. Baixar a imagem oficial `apache/spark:3.5.9-scala2.12-java17-python3-ubuntu`;
2. Instalar dependências extras de sistema (`curl`, `procps`);
3. Instalar dependências Python do `requirements.txt`;
4. Copiar `app/` e `data/` para dentro da imagem.

---

## 4. Subindo o cluster (Master + 2 Workers)

```bash
docker compose up -d
```

Verifique os containers:

```bash
docker compose ps
```

Você deve ver `spark-master`, `spark-worker-1` e `spark-worker-2` com status `Up`.

Acompanhe os logs do master até ver `I have been elected leader! New state: ALIVE`:

```bash
docker compose logs -f spark-master
```

### Portas expostas

| Porta (host) | Serviço        | Descrição                                                       |
| ------------ | --------------- | ----------------------------------------------------------------- |
| `8080`     | Master Web UI   | Lista workers registrados e aplicações                          |
| `7077`     | Master RPC      | Endereço`spark://spark-master:7077` usado por workers/clientes |
| `8081`     | Worker 1 Web UI | Recursos e executors do worker 1                                  |
| `8082`     | Worker 2 Web UI | Recursos e executors do worker 2                                  |
| `4040`     | Application UI  | Sobe automaticamente enquanto um job/shell está rodando          |

Abra `http://localhost:8080` no navegador — a tabela **Workers** deve listar os
dois workers com status `ALIVE`.

---

## 5. Validando a instalação

### Opção A — `spark-submit` com o job PySpark de exemplo

```bash
docker exec -it spark-master /opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --executor-memory 1g \
  --total-executor-cores 2 \
  /opt/spark-apps/word_count.py
```

Saída esperada (resumo):

```
[OK] SparkContext criado. Master: spark://spark-master:7077
[OK] Executors ativos: N slots de paralelismo

=== Resultado do WordCount ===
spark            4
de               4
docker           2
...

[SUCESSO] Job executado corretamente no cluster Spark.
```

Enquanto o job roda, `http://localhost:4040` mostra a UI da aplicação (estágios,
tasks, storage).

### Opção B — `pyspark` interativo, conectado ao cluster

```bash
docker exec -it spark-master /opt/spark/bin/pyspark \
  --master spark://spark-master:7077
```

Dentro do shell:

```python
>>> spark.sparkContext.master
'spark://spark-master:7077'

>>> rdd = spark.sparkContext.parallelize(range(1000), 10)
>>> rdd.sum()
499500
```

Se retornar `499500`, o cluster está distribuindo o trabalho corretamente entre
master e workers.

### Opção C — `spark-shell` (Scala), para checagem rápida sem PySpark

```bash
docker exec -it spark-master /opt/spark/bin/spark-shell \
  --master spark://spark-master:7077
```

```scala
scala> sc.parallelize(1 to 1000).sum()
res0: Double = 500500.0
```

---

## 6. Executando seu próprio código Python

Você tem três formas de rodar código no cluster, dependendo do fluxo de trabalho:

### A. Script batch (produção / pipelines agendados)

Salve seu `.py` em `app/` (o bind mount já leva pro container automaticamente,
sem rebuild) e rode:

```bash
make submit JOB=/opt/spark-apps/meu_script.py
```

Esse é o caminho recomendado para jobs que rodam sozinhos, de ponta a ponta,
sem interação — o padrão usado em produção (agendado por cron, Airflow etc.).

### B. Shell interativo (exploração rápida, sem notebook)

```bash
make pyspark        # Python
make spark-shell    # Scala
```

### C. Jupyter Lab (desenvolvimento exploratório, análise, prototipagem)

Sim, dá pra rodar PySpark via notebook — adicionei um serviço dedicado
(`spark-notebook`) que atua como **cliente** do cluster: o notebook roda o
driver do Spark, mas a execução distribuída acontece nos workers de verdade.

```bash
make notebook       # builda (na primeira vez) e sobe o Jupyter Lab
make notebook-url   # mostra a URL com o token de acesso
```

Abra a URL retornada no navegador (algo como
`http://127.0.0.1:8888/lab?token=...`). Você verá `notebooks/00_getting_started.ipynb`
já pronto, mostrando como conectar no cluster:

```python
import findspark
findspark.init()

from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    .appName("meu-notebook")
    .master("spark://spark-master:7077")   # importante: conecta no cluster real
    .getOrCreate()
)
```

Pontos importantes sobre esse serviço:

- **Imagem separada** (`Dockerfile.notebook`): Jupyter/`findspark`/`ipykernel`
  ficam só na imagem do cliente, não na imagem de master/worker que "seria"
  deployada em produção — mantém aquela imagem enxuta.
- **`notebooks/` é `rw`**, `app/` e `data/` continuam `:ro` — o notebook pode
  salvar `.ipynb` localmente, mas não sobrescreve código/dados de origem.
- **`.master("spark://spark-master:7077")`**: se você omitir isso, o
  `SparkSession` roda em `local[*]` **dentro do próprio container do
  notebook**, sem usar os workers — funciona, mas não testa o cluster de
  verdade.
- O Jupyter mantém autenticação por token por padrão (não desabilitei); use
  `make notebook-url` pra pegar o link já com o token.

## 7. Atalhos com Makefile

Em vez de digitar os comandos completos, use o `Makefile` incluído:

```bash
make help          # lista todos os comandos disponíveis
make build          # docker compose build
make up             # sobe o cluster
make ps             # status dos containers
make logs-master    # logs só do master
make wordcount      # roda o job de validação word_count.py
make submit JOB=/opt/spark-apps/meu_job.py   # roda outro job seu
make pyspark        # shell PySpark interativo conectado ao cluster
make spark-shell    # shell Scala interativo conectado ao cluster
make ui             # abre http://localhost:8080 no navegador
make down           # para o cluster
make clean          # para e remove volumes de log
make notebook       # sobe o Jupyter Lab (builda na primeira vez)
make notebook-url   # mostra a URL de acesso com token
```

## 8. Encerrando o ambiente

```bash
# Para os containers, mantém volumes (logs)
docker compose down

# Remove também os volumes nomeados (ex.: spark-logs)
docker compose down -v
```

---

## 9. Boas práticas adotadas (produção)

- **Imagem oficial versionada** (Spark+Scala+Java+SO explícitos na tag) em vez de `latest`,
  garantindo builds reprodutíveis.
- **Usuário não-root** (`spark`) dentro do container, evitando execução de daemons como root.
- **`.dockerignore`** para builds menores e mais rápidos.
- **Multi-worker** com `SPARK_WORKER_CORES`/`SPARK_WORKER_MEMORY` configuráveis via
  variável de ambiente, para simular alocação de recursos de um cluster real.
- **Healthcheck** no master, garantindo que os workers só sobem depois que o master
  está de fato pronto (`depends_on: condition: service_healthy`).
- **Volumes** para código (`app/`) e dados (`data/`), separando artefato de imagem
  (o binário do Spark) de artefato de aplicação (seus jobs), o que evita rebuild
  de imagem a cada alteração de código durante desenvolvimento.
- **Portas documentadas** de acordo com a documentação oficial de Spark Standalone
  Mode (master RPC 7077, Master UI 8080, Worker UI 8081+, Application UI 4040+).
- **Volume de log por serviço** (`spark-master-logs`, `spark-worker-1-logs`,
  `spark-worker-2-logs`): master e workers **não** compartilham o mesmo volume de
  log, evitando colisão de escrita entre daemons diferentes.
- **Bind mount `:ro`** para `app/` e `data/`: os containers só precisam LER esses
  artefatos, nunca escrever neles — reduz superfície de erro/ataque.

> **Limite importante:** bind mounts (`./app:/opt/spark-apps`) só funcionam
> porque master e workers rodam no **mesmo host** Docker. Em um cluster real
> multi-host (Swarm, Kubernetes) isso não se sustenta — cada nó veria um
> filesystem local diferente. Para produção distribuída de fato, o padrão é
> **assar o código na imagem** (via `COPY` no Dockerfile, sem bind mount) e
> versionar a imagem por tag, ou usar armazenamento compartilhado (S3, HDFS,
> NFS) para os dados. O bind mount aqui é uma otimização de **produtividade em
> desenvolvimento local**, não o padrão de deploy final.

## Referências

- Download oficial e imagens Docker: https://spark.apache.org/downloads.html
- Spark Standalone Mode (portas, `spark-class`, arquitetura master/worker):
  https://spark.apache.org/docs/latest/spark-standalone.html
- Repositório oficial das imagens Docker: https://github.com/apache/spark-docker
- Docker Official Image (`spark`): https://hub.docker.com/_/spa

# Apache Spark em Docker — Guia Completo (Arch Linux)

Cluster standalone (1 Master + 2 Workers) usando a imagem **oficial** do Apache Spark
como base, seguindo o padrão documentado em `spark.apache.org/docs/latest/spark-standalone.html`
e no repositório oficial de imagens `github.com/apache/spark-docker`.

Estrutura do projeto:

```
spark-docker/
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── .dockerignore
├── app/
│   └── word_count.py      # job de validação (PySpark)
└── data/
    └── sample.txt         # dados de exemplo
```

---

## 1. Por que essa imagem base

Recomendação: **imagem oficial `apache/spark`** (mantida pela própria Apache Software
Foundation), em vez de construir do zero sobre `ubuntu:latest`/`debian:slim`.

| Critério                                                  | `apache/spark` (oficial)                 | Ubuntu/Debian "cru"                        |
| ---------------------------------------------------------- | ------------------------------------------ | ------------------------------------------ |
| JDK correto pré-instalado e testado                       | Sim                                        | Você instala e valida manualmente         |
| Download/checksum/assinatura GPG do Spark                  | Já feito pelo pipeline oficial de release | Você precisa baixar e verificar           |
| Usuário não-root configurado                             | Sim (`spark`)                            | Você precisa configurar                   |
| Testado em CI pela comunidade Spark (build/standalone/k8s) | Sim                                        | N/A                                        |
| Reprodutibilidade de versão (Spark+Scala+Java+SO na tag)  | Sim, explícito na tag                     | Depende de como você escreve o Dockerfile |

A tag usada aqui (`3.5.9-scala2.12-java17-python3-ubuntu`) já é baseada em Ubuntu —
ou seja, você ganha a base Ubuntu que pediu **e** todo o trabalho de empacotamento
do Spark já validado pela Apache, ao invés de refazer esse trabalho manualmente.
Isso é o que a documentação oficial recomenda: usar as imagens publicadas em
`hub.docker.com/r/apache/spark` ou `_/spark` (Docker Official Image).

> Nota sobre versão: no momento em que este guia foi gerado, `3.5.9` é a série
> **LTS** mais recente da linha 3.5.x e `4.2.0` é a última major (Scala 2.13).
> Se seu projeto puder migrar para Spark 4.x, troque `SPARK_VERSION`/`SCALA_VERSION`
> no topo do `Dockerfile` — o restante do guia não muda.

---

## 2. Pré-requisitos no Arch Linux

```bash
# Docker e Docker Compose plugin
sudo pacman -S docker docker-compose

# Habilitar e iniciar o serviço
sudo systemctl enable --now docker.service

# (opcional, recomendado) usar docker sem sudo
sudo usermod -aG docker $USER
newgrp docker

# Validar instalação
docker --version
docker compose version
```

---

## 3. Build da imagem customizada

Dentro da pasta `spark-docker/`:

```bash
docker compose build
```

Isso vai:

1. Baixar a imagem oficial `apache/spark:3.5.9-scala2.12-java17-python3-ubuntu`;
2. Instalar dependências extras de sistema (`curl`, `procps`);
3. Instalar dependências Python do `requirements.txt`;
4. Copiar `app/` e `data/` para dentro da imagem.

---

## 4. Subindo o cluster (Master + 2 Workers)

```bash
docker compose up -d
```

Verifique os containers:

```bash
docker compose ps
```

Você deve ver `spark-master`, `spark-worker-1` e `spark-worker-2` com status `Up`.

Acompanhe os logs do master até ver `I have been elected leader! New state: ALIVE`:

```bash
docker compose logs -f spark-master
```

### Portas expostas

| Porta (host) | Serviço        | Descrição                                                       |
| ------------ | --------------- | ----------------------------------------------------------------- |
| `8080`     | Master Web UI   | Lista workers registrados e aplicações                          |
| `7077`     | Master RPC      | Endereço`spark://spark-master:7077` usado por workers/clientes |
| `8081`     | Worker 1 Web UI | Recursos e executors do worker 1                                  |
| `8082`     | Worker 2 Web UI | Recursos e executors do worker 2                                  |
| `4040`     | Application UI  | Sobe automaticamente enquanto um job/shell está rodando          |

Abra `http://localhost:8080` no navegador — a tabela **Workers** deve listar os
dois workers com status `ALIVE`.

---

## 5. Validando a instalação

### Opção A — `spark-submit` com o job PySpark de exemplo

```bash
docker exec -it spark-master /opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --executor-memory 1g \
  --total-executor-cores 2 \
  /opt/spark-apps/word_count.py
```

Saída esperada (resumo):

```
[OK] SparkContext criado. Master: spark://spark-master:7077
[OK] Executors ativos: N slots de paralelismo

=== Resultado do WordCount ===
spark            4
de               4
docker           2
...

[SUCESSO] Job executado corretamente no cluster Spark.
```

Enquanto o job roda, `http://localhost:4040` mostra a UI da aplicação (estágios,
tasks, storage).

### Opção B — `pyspark` interativo, conectado ao cluster

```bash
docker exec -it spark-master /opt/spark/bin/pyspark \
  --master spark://spark-master:7077
```

Dentro do shell:

```python
>>> spark.sparkContext.master
'spark://spark-master:7077'

>>> rdd = spark.sparkContext.parallelize(range(1000), 10)
>>> rdd.sum()
499500
```

Se retornar `499500`, o cluster está distribuindo o trabalho corretamente entre
master e workers.

### Opção C — `spark-shell` (Scala), para checagem rápida sem PySpark

```bash
docker exec -it spark-master /opt/spark/bin/spark-shell \
  --master spark://spark-master:7077
```

```scala
scala> sc.parallelize(1 to 1000).sum()
res0: Double = 500500.0
```

---

## 6. Atalhos com Makefile

Em vez de digitar os comandos completos, use o `Makefile` incluído:

```bash
make help          # lista todos os comandos disponíveis
make build          # docker compose build
make up             # sobe o cluster
make ps             # status dos containers
make logs-master    # logs só do master
make wordcount      # roda o job de validação word_count.py
make submit JOB=/opt/spark-apps/meu_job.py   # roda outro job seu
make pyspark        # shell PySpark interativo conectado ao cluster
make spark-shell    # shell Scala interativo conectado ao cluster
make ui             # abre http://localhost:8080 no navegador
make down           # para o cluster
make clean          # para e remove volumes de log
```

## 7. Encerrando o ambiente

```bash
# Para os containers, mantém volumes (logs)
docker compose down

# Remove também os volumes nomeados (ex.: spark-logs)
docker compose down -v
```

---

## 8. Boas práticas adotadas (produção)

- **Imagem oficial versionada** (Spark+Scala+Java+SO explícitos na tag) em vez de `latest`,
  garantindo builds reprodutíveis.
- **Usuário não-root** (`spark`) dentro do container, evitando execução de daemons como root.
- **`.dockerignore`** para builds menores e mais rápidos.
- **Multi-worker** com `SPARK_WORKER_CORES`/`SPARK_WORKER_MEMORY` configuráveis via
  variável de ambiente, para simular alocação de recursos de um cluster real.
- **Healthcheck** no master, garantindo que os workers só sobem depois que o master
  está de fato pronto (`depends_on: condition: service_healthy`).
- **Volumes** para código (`app/`) e dados (`data/`), separando artefato de imagem
  (o binário do Spark) de artefato de aplicação (seus jobs), o que evita rebuild
  de imagem a cada alteração de código durante desenvolvimento.
- **Portas documentadas** de acordo com a documentação oficial de Spark Standalone
  Mode (master RPC 7077, Master UI 8080, Worker UI 8081+, Application UI 4040+).
- **Volume de log por serviço** (`spark-master-logs`, `spark-worker-1-logs`,
  `spark-worker-2-logs`): master e workers **não** compartilham o mesmo volume de
  log, evitando colisão de escrita entre daemons diferentes.
- **Bind mount `:ro`** para `app/` e `data/`: os containers só precisam LER esses
  artefatos, nunca escrever neles — reduz superfície de erro/ataque.

> **Limite importante:** bind mounts (`./app:/opt/spark-apps`) só funcionam
> porque master e workers rodam no **mesmo host** Docker. Em um cluster real
> multi-host (Swarm, Kubernetes) isso não se sustenta — cada nó veria um
> filesystem local diferente. Para produção distribuída de fato, o padrão é
> **assar o código na imagem** (via `COPY` no Dockerfile, sem bind mount) e
> versionar a imagem por tag, ou usar armazenamento compartilhado (S3, HDFS,
> NFS) para os dados. O bind mount aqui é uma otimização de **produtividade em
> desenvolvimento local**, não o padrão de deploy final.

## Referências

- Download oficial e imagens Docker: https://spark.apache.org/downloads.html
- Spark Standalone Mode (portas, `spark-class`, arquitetura master/worker):
  https://spark.apache.org/docs/latest/spark-standalone.html
- Repositório oficial das imagens Docker: https://github.com/apache/spark-docker
- Docker Official Image (`spark`): https://hub.docker.com/_/spark

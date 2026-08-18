# ==============================================================================
# Dockerfile.notebook - Cliente Jupyter Lab para o cluster Spark
# ==============================================================================
# Propositalmente um Dockerfile SEPARADO do Dockerfile principal (master/worker):
#   - A imagem de master/worker que roda em produção não deve carregar Jupyter,
#     ipykernel etc. Isso é ferramenta de desenvolvimento, não de runtime do
#     cluster. Separar evita inflar/expor a imagem "de produção".
#   - Este container atua só como CLIENTE: ele roda o driver do Spark (quem
#     inicia o SparkSession) mas delega a execução distribuída para o cluster
#     via spark://spark-master:7077, os workers reais continuam nos outros
#     containers.
# ==============================================================================

ARG SPARK_VERSION=3.5.9
ARG SCALA_VERSION=2.12
ARG JAVA_VERSION=17

FROM apache/spark:${SPARK_VERSION}-scala${SCALA_VERSION}-java${JAVA_VERSION}-python3-ubuntu

LABEL description="Jupyter Lab como cliente PySpark do cluster spark-standalone"

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt      /opt/spark/work-dir/requirements.txt
COPY requirements-dev.txt  /opt/spark/work-dir/requirements-dev.txt
RUN pip3 install --no-cache-dir \
      -r /opt/spark/work-dir/requirements.txt \
      -r /opt/spark/work-dir/requirements-dev.txt

RUN mkdir -p /opt/spark-notebooks && chown -R spark:spark /opt/spark-notebooks

# A imagem oficial do Spark não define HOME pro usuário "spark" (cai em
# /nonexistent), o que quebra o Jupyter ao tentar criar ~/.local/share/jupyter.
# Criamos um HOME de verdade, gravável, e apontamos a variável pra lá.
RUN mkdir -p /home/spark && chown -R spark:spark /home/spark
ENV HOME=/home/spark

ENV SPARK_HOME=/opt/spark
ENV PATH="${SPARK_HOME}/bin:${PATH}"

USER spark

WORKDIR /opt/spark-notebooks

EXPOSE 8888

# Sem desabilitar token/senha: Jupyter gera um token de acesso por padrão.
# É uma boa prática manter isso mesmo em ambiente local (hábito de produção).
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser"]
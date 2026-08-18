ARG SPARK_VERSION=3.5.9
ARG SCALA_VERSION=2.12  
ARG JAVA_VERSION=17

# Tag oficial: <spark>-scala<versao>-java<versao>-python3-ubuntu
FROM apache/spark:${SPARK_VERSION}-scala${SCALA_VERSION}-java${JAVA_VERSION}-python3-ubuntu

LABEL maintainer="data-engineering" \
      description="Ambiente Apache Spark standalone via Docker (Master/Worker)" \
      spark.version="${SPARK_VERSION}"

# A imagem oficial roda como usuário "spark" (não-root). Precisamos do root
# apenas temporariamente para instalar pacotes adicionais do sistema.
USER root

# Dependências extras de sistema:
#   curl      -> healthchecks / debug de rede dentro do container
#   procps    -> ps/top, úteis para monitorar JVMs do Spark
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Dependências Python adicionais do projeto (PySpark já vem embutido na imagem
# via $SPARK_HOME/python, aqui só adicionamos libs extras que seus jobs usem).
COPY requirements.txt /opt/spark/work-dir/requirements.txt
RUN pip3 install --no-cache-dir -r /opt/spark/work-dir/requirements.txt

# Copia os jobs/aplicações e dados de exemplo para dentro da imagem.
# Em produção, montar isso via volume (ver docker-compose.yml) para não
# precisar rebuildar a imagem a cada alteração de código.
COPY app/  /opt/spark-apps/
COPY data/ /opt/spark-data/

ENV SPARK_HOME=/opt/spark
ENV PATH="${SPARK_HOME}/bin:${SPARK_HOME}/sbin:${PATH}"

WORKDIR /opt/spark-apps

# Volta para o usuário não-root definido pela imagem oficial (segurança em produção:
# nunca rodar o daemon do Spark como root).
USER spark

# O ENTRYPOINT oficial da imagem (/opt/entrypoint.sh) já sabe iniciar
# master, worker, driver, executor ou um shell, de acordo com o primeiro
# argumento recebido no `command:` do docker-compose.
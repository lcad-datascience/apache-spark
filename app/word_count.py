"""
Job de validação do cluster Spark: contagem de palavras (WordCount).

Uso (dentro do container, apontando para o master do cluster):

    docker exec -it spark-master /opt/spark/bin/spark-submit \
        --master spark://spark-master:7077 \
        /opt/spark-apps/word_count.py
"""

from pyspark.sql import SparkSession

def main():
    spark = (
        SparkSession.builder
        .appName("ValidacaoClusterSpark-WordCount")
        .getOrCreate()
    )

    sc = spark.sparkContext
    print(f"[OK] SparkContext criado. Master: {sc.master}")
    print(f"[OK] Executors ativos: {sc.defaultParallelism} slots de paralelismo")

    caminho_arquivo = "/opt/spark-data/sample.txt"
    linhas = sc.textFile(caminho_arquivo)

    contagem = (
        linhas.flatMap(lambda linha: linha.split(" "))
        .map(lambda palavra: (palavra.lower().strip(".,!?"), 1))
        .filter(lambda par: par[0] != "")
        .reduceByKey(lambda a, b: a + b)
        .sortBy(lambda par: par[1], ascending=False)
    )

    resultado = contagem.collect()

    print("\n=== Resultado do WordCount ===")
    for palavra, total in resultado[:15]:
        print(f"{palavra:<15} {total}")

    print("\n[SUCESSO] Job executado corretamente no cluster Spark.")
    spark.stop()

if __name__ == "__main__":
    main()
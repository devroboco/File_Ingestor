# 📘 File Ingestor — LocalStack (S3 + Lambda + DynamoDB + API Gateway)

Pipeline local que simula uma arquitetura **serverless**:  
ao enviar um arquivo para o S3, uma **Lambda** é acionada para extrair metadados, salvar no **DynamoDB**, mover o arquivo para outro bucket e expor os dados via **API Gateway**.

---

## 🧠 Objetivo do Desafio
Construir um pipeline local onde:

1. O arquivo é enviado a um bucket S3 (`ingestor-raw`);
2. Uma **Lambda** é disparada por evento `ObjectCreated`, extrai metadados (nome, tamanho, hash) e grava um item no DynamoDB;
3. A Lambda move o arquivo para `ingestor-processed` e atualiza o item (`status=PROCESSED`);
4. Uma **API (API Gateway + Lambda)** lista/consulta os itens no Dynamo.

---

## ⚙️ Stack utilizada
- **LocalStack 3** — simula S3, DynamoDB, Lambda, API Gateway e Logs localmente.  
- **Python (boto3)** — código das Lambdas.  
- **Docker e Docker Compose** — orquestram todo o ambiente.  
- **Scripts shell (`.sh`)** — automatizam criação e testes do fluxo.  

---

## 🗂️ Estrutura do Projeto
├─ docker-compose.yml
├─ run.sh # sobe o ambiente e provisiona recursos
├─ down.sh # derruba tudo
├─ lambdas/
│ ├─ ingest_lambda.py # extrai metadados, grava no Dynamo e move o arquivo
│ └─ api_lambda.py # expõe os endpoints GET /files e /files/{id}
└─ scripts/
├─ setup_resources.sh # cria buckets, tabela, lambdas e API
└─ test_flow.sh # executa o fluxo end-to-end e imprime resultados


---

## Como executar

### Dar permissão aos scripts (somente uma vez)
```bash
chmod +x run.sh down.sh scripts/*.sh
```

### Subir o ambiente
```bash
./run.sh
```

### Testar e gerar saídas para screenshots
```bash
MSYS_NO_PATHCONV=1 docker exec -it localstack bash -lc "/scripts/test_flow.sh"
```

### Derrubar o ambiente
```bash
./down.sh
```

## Breve Explicação das Decisões

### Para atender aos requisitos do desafio, foram tomadas algumas decisões técnicas importantes:

- Uso do LocalStack: permite simular os serviços da AWS localmente, garantindo um ambiente gratuito e controlado para desenvolvimento e testes.

- Empacotamento automático das Lambdas: o script setup_resources.sh utiliza o módulo zipfile do Python para criar o pacote lambdas.zip dentro do container, eliminando a necessidade de ferramentas externas como o zip.

- Scripts idempotentes: todos os scripts podem ser executados várias vezes sem causar duplicação de recursos, o que simplifica os testes e reconfigurações.

- Lambda Proxy Integration: facilita o mapeamento de rotas no API Gateway, permitindo que as requisições HTTP sejam encaminhadas diretamente às funções Lambda.

- Chave primária no formato file#<nome_do_arquivo>: facilita a identificação e recuperação dos registros no DynamoDB.

- Serialização de dados com default=str: corrige erros ao converter objetos Decimal e datetime para JSON, garantindo compatibilidade no retorno da API.

- Decodificação de URLs (unquote): adicionada ao api_lambda.py para permitir que o caractere # (usado na chave primária) seja corretamente interpretado ao acessar /files/{id}.

## Evidências do Funcionamento
### Upload no S3
O primeiro print mostra o momento em que o arquivo é enviado ao bucket ingestor-raw, o que aciona automaticamente a Lambda de ingestão.

<img width="514" height="39" alt="Captura de tela 2025-10-22 232711" src="https://github.com/user-attachments/assets/f4fe00ac-a62e-48d1-97d1-893495391255" />

### Execução da Lambda
O segundo print exibe os logs da função ingest-lambda no CloudWatch (simulado pelo LocalStack).
Ele comprova que a função foi executada em resposta ao evento ObjectCreated do S3.

<img width="1841" height="56" alt="Captura de tela 2025-10-22 232832" src="https://github.com/user-attachments/assets/97572640-3380-46cc-b415-2901aad1d26c" />

### Item Gravado no DynamoDB
O terceiro print mostra a saída da consulta à tabela files no DynamoDB, com o registro do arquivo processado contendo seus metadados principais: bucket, key, size, etag, status=PROCESSED, processedAt, contentType e checksum.

<img width="591" height="551" alt="Captura de tela 2025-10-22 232858" src="https://github.com/user-attachments/assets/2ca6b5fa-5dac-4db5-80c9-9c44fa2577f7" />

### API Respondendo
O último print mostra a API em funcionamento, retornando a lista de arquivos processados pelo endpoint /files e a consulta individual pelo endpoint /files/{id}.

<img width="1843" height="144" alt="Captura de tela 2025-10-22 232921" src="https://github.com/user-attachments/assets/1b47344f-fd72-400f-a0ad-f4b2fb77c1ac" />



# Portable AWS App - Python Version

Esta é a versão Python do projeto Portable AWS App, convertida do código Node.js original. O projeto demonstra diferentes arquiteturas de software usando Flask como framework web.

## Estrutura do Projeto

```
src-python/
├── 01-Monolith/           # Arquitetura Monolítica
├── 02-Layered/            # Arquitetura em Camadas
├── 04-CleanArchitecture/  # Arquitetura Limpa
├── requirements.txt       # Dependências Python
└── README.md             # Este arquivo
```

## Pré-requisitos

- Python 3.8+
- pip (gerenciador de pacotes Python)

## Instalação

1. Navegue até a pasta src-python:
```bash
cd src-python
```

2. Instale as dependências:
```bash
pip install -r requirements.txt
```

## Executando as Aplicações

### Arquitetura Monolítica
```bash
cd 01-Monolith
python server.py
```

### Arquitetura em Camadas
```bash
cd 02-Layered
python -m src-python.02-Layered.server
```

### Arquitetura Limpa
```bash
cd 04-CleanArchitecture
python server.py
```

## Endpoints Disponíveis

Todas as arquiteturas expõem os mesmos endpoints:

- `GET /health` - Verificação de saúde
- `GET /version` - Versão da arquitetura
- `POST /users` - Criar usuário
- `GET /users` - Listar todos os usuários
- `GET /users/{id}` - Obter usuário por ID
- `DELETE /users/{id}` - Deletar usuário por ID

## Exemplo de Uso

### Criar um usuário:
```bash
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name": "João Silva", "email": "joao@example.com"}'
```

### Listar usuários:
```bash
curl http://localhost:8080/users
```

## Executando Testes

```bash
# Executar todos os testes
pytest

# Executar testes de uma arquitetura específica
pytest 01-Monolith/test_app.py

# Executar com cobertura
pytest --cov=.
```

## Diferenças da Versão Node.js

1. **Framework Web**: Express.js → Flask
2. **Linguagem**: TypeScript → Python
3. **Gerenciamento de Dependências**: npm → pip
4. **Testes**: Jest → pytest
5. **Async/Await**: Nativo no Node.js → asyncio no Python
6. **Logging**: console.log → logging module

## Arquiteturas Implementadas

### 1. Monolítica (01-Monolith)
- Toda a lógica em um único arquivo
- Simples e direta
- Ideal para projetos pequenos

### 2. Em Camadas (02-Layered)
- Separação em camadas: Controllers, Services, Repositories, Models
- Melhor organização do código
- Facilita manutenção

### 3. Limpa (04-CleanArchitecture)
- Separação clara entre domínio, aplicação e infraestrutura
- Inversão de dependências
- Altamente testável e flexível

## Configuração de Porta

Por padrão, todas as aplicações executam na porta 8080. Para alterar:

```bash
export PORT=3000
python server.py
```

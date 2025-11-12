.PHONY: help install test clean run-monolith run-layered run-clean

help:
	@echo "Comandos disponíveis:"
	@echo "  install      - Instalar dependências"
	@echo "  test         - Executar todos os testes"
	@echo "  test-cov     - Executar testes com cobertura"
	@echo "  run-monolith - Executar arquitetura monolítica"
	@echo "  run-layered  - Executar arquitetura em camadas"
	@echo "  run-clean    - Executar arquitetura limpa"
	@echo "  clean        - Limpar arquivos temporários"

install:
	pip install -r requirements.txt

test:
	pytest -v

test-cov:
	pytest --cov=. --cov-report=html --cov-report=term

run-monolith:
	python run.py monolith

run-layered:
	python run.py layered

run-clean:
	python run.py clean

clean:
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
	rm -rf htmlcov/
	rm -rf .pytest_cache/
	rm -rf .coverage

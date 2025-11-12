#!/usr/bin/env python3
"""
Script para executar diferentes arquiteturas da aplicação Python
"""

import sys
import os
import argparse

def run_monolith():
    """Executa a arquitetura monolítica"""
    print("🚀 Iniciando Arquitetura Monolítica...")
    os.chdir('01-Monolith')
    os.system('python server.py')

def run_layered():
    """Executa a arquitetura em camadas"""
    print("🚀 Iniciando Arquitetura em Camadas...")
    os.system('python -m 02-Layered.server')

def run_clean():
    """Executa a arquitetura limpa"""
    print("🚀 Iniciando Arquitetura Limpa...")
    os.chdir('04-CleanArchitecture')
    os.system('python server.py')

def main():
    parser = argparse.ArgumentParser(description='Executar aplicação Python com diferentes arquiteturas')
    parser.add_argument('architecture', 
                       choices=['monolith', 'layered', 'clean'],
                       help='Arquitetura a ser executada')
    
    args = parser.parse_args()
    
    # Salvar diretório atual
    original_dir = os.getcwd()
    
    try:
        if args.architecture == 'monolith':
            run_monolith()
        elif args.architecture == 'layered':
            run_layered()
        elif args.architecture == 'clean':
            run_clean()
    finally:
        # Voltar ao diretório original
        os.chdir(original_dir)

if __name__ == '__main__':
    main()
